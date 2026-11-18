import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

function maskError(value: string) {
  return value.replace(/Bearer\s+\S+/gi, "Bearer [redacted]").slice(0, 450);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "unauthorized" }, 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "unauthorized" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: { attendance_id?: string } = {};
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const attendanceId = String(body.attendance_id || "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(attendanceId)) {
    return json({ error: "invalid_attendance_id" }, 400);
  }

  const { data: attendance, error: attendanceError } = await admin
    .from("coachingos_records")
    .select("id,institute_id,record_type,record_data")
    .eq("id", attendanceId)
    .eq("record_type", "attendance")
    .maybeSingle();
  if (attendanceError || !attendance) return json({ error: "attendance_not_found" }, 404);
  if (String(attendance.record_data?.status || "") !== "Present") {
    return json({ error: "attendance_not_present" }, 409);
  }

  const { data: membership } = await admin
    .from("institute_members")
    .select("role")
    .eq("institute_id", attendance.institute_id)
    .eq("user_id", authData.user.id)
    .maybeSingle();
  if (!membership || !["owner", "admin", "manager", "teacher", "receptionist"].includes(membership.role)) {
    return json({ error: "forbidden" }, 403);
  }

  const studentId = String(attendance.record_data?.student_record_id || "");
  if (!studentId) return json({ error: "student_record_id_missing" }, 422);
  const { data: student, error: studentError } = await admin
    .from("coachingos_records")
    .select("record_data")
    .eq("id", studentId)
    .eq("institute_id", attendance.institute_id)
    .eq("record_type", "students")
    .maybeSingle();
  if (studentError || !student) return json({ error: "student_not_found" }, 404);
  const studentData = student.record_data || {};
  if (String(studentData.guardian_report_consent || "").trim().toLowerCase() !== "yes") {
    return json({ error: "guardian_consent_not_yes" }, 403);
  }

  const email = String(studentData.guardian_email || "").trim();
  const phone = String(studentData.guardian_phone || "").trim();
  const { data: claimed, error: claimError } = await admin.rpc("claim_coachingos_guardian_deliveries", {
    _institute_id: attendance.institute_id,
    _attendance_record_id: attendanceId,
  });
  if (claimError) return json({ error: "queue_claim_failed" }, 500);
  if (!claimed?.length) return json({ ok: true, processed: 0, message: "No queued deliveries." });

  const results: Array<{ channel: string; status: string }> = [];
  for (const item of claimed) {
    try {
      if (item.channel === "email") {
        const apiKey = Deno.env.get("RESEND_API_KEY");
        const from = Deno.env.get("EMAIL_FROM");
        if (!apiKey || !from || !email) {
          await admin.from("guardian_delivery_logs").update({
            status: "blocked", provider: "Resend", error_message: "provider_not_configured",
            updated_at: new Date().toISOString(),
          }).eq("id", item.id);
          results.push({ channel: "email", status: "blocked" });
          continue;
        }
        const message = `Attendance update for ${studentData.name || "your student"}: Present on ${attendance.record_data.date || new Date().toISOString().slice(0, 10)}.`;
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from,
            to: [email],
            subject: "Attendance update - CoachingOS",
            text: message,
          }),
        });
        const responseText = await response.text();
        let responseData: Record<string, unknown> = {};
        try { responseData = JSON.parse(responseText); } catch { /* provider returned non-JSON */ }
        if (!response.ok) throw new Error(`Resend ${response.status}: ${maskError(responseText)}`);
        await admin.from("guardian_delivery_logs").update({
          status: "sent", provider: "Resend",
          provider_message_id: String(responseData.id || ""),
          error_message: null, sent_at: new Date().toISOString(), updated_at: new Date().toISOString(),
        }).eq("id", item.id);
        results.push({ channel: "email", status: "sent" });
      } else if (item.channel === "sms") {
        const endpoint = Deno.env.get("SMS_GATEWAY_URL");
        const apiKey = Deno.env.get("SMS_GATEWAY_API_KEY");
        const senderId = Deno.env.get("SMS_SENDER_ID");
        if (!endpoint || !apiKey || !phone) {
          await admin.from("guardian_delivery_logs").update({
            status: "blocked", provider: "SMS gateway",
            error_message: "provider_not_configured", updated_at: new Date().toISOString(),
          }).eq("id", item.id);
          results.push({ channel: "sms", status: "blocked" });
          continue;
        }
        const message = `CoachingOS: ${studentData.name || "Student"} was marked Present on ${attendance.record_data.date || new Date().toISOString().slice(0, 10)}.`;
        const response = await fetch(endpoint, {
          method: "POST",
          headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({ to: phone, message, sender_id: senderId || undefined }),
        });
        const responseText = await response.text();
        let responseData: Record<string, unknown> = {};
        try { responseData = JSON.parse(responseText); } catch { /* provider returned non-JSON */ }
        if (!response.ok) throw new Error(`SMS gateway ${response.status}: ${maskError(responseText)}`);
        await admin.from("guardian_delivery_logs").update({
          status: "sent", provider: "SMS gateway",
          provider_message_id: String(responseData.message_id || responseData.id || ""),
          error_message: null, sent_at: new Date().toISOString(), updated_at: new Date().toISOString(),
        }).eq("id", item.id);
        results.push({ channel: "sms", status: "sent" });
      }
    } catch (error) {
      const message = error instanceof Error ? maskError(error.message) : "delivery_failed";
      await admin.from("guardian_delivery_logs").update({
        status: "failed", error_message: message, updated_at: new Date().toISOString(),
      }).eq("id", item.id);
      results.push({ channel: item.channel, status: "failed" });
    }
  }
  return json({ ok: true, processed: results.length, results });
});
