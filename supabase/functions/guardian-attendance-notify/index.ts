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

function safeError(value: string) {
  return value
    .replace(/Bearer\s+\S+/gi, "Bearer [redacted]")
    .replace(/(api[_-]?key|token|secret|password)\s*[:=]\s*[^\s,"]+/gi, "$1=[redacted]")
    .slice(0, 350);
}

function normalizeBangladeshMobile(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  let national = digits;
  if (national.startsWith("00880")) national = national.slice(5);
  else if (national.startsWith("880")) national = national.slice(3);
  if (national.length === 11 && /^01[3-9]\d{8}$/.test(national)) {
    return "+880" + national.slice(1);
  }
  return null;
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

  const phone = String(studentData.guardian_phone || "").trim();
  const normalizedPhone = normalizeBangladeshMobile(phone);
  const endpoint = Deno.env.get("SMS_GATEWAY_URL");
  const apiKey = Deno.env.get("SMS_GATEWAY_API_KEY");
  const senderId = Deno.env.get("SMS_SENDER_ID");

  // Keep deliveries queued until a provider is configured; never consume attempts while offline.
  if (!endpoint || !apiKey) {
    return json({
      ok: true,
      processed: 0,
      queued: true,
      message: "SMS provider is not configured; delivery remains queued.",
    });
  }

  const { data: claimed, error: claimError } = await admin.rpc("claim_coachingos_guardian_deliveries", {
    _institute_id: attendance.institute_id,
    _attendance_record_id: attendanceId,
  });
  if (claimError) return json({ error: "queue_claim_failed" }, 500);
  if (!claimed?.length) return json({ ok: true, processed: 0, message: "No queued SMS deliveries." });
  const results: Array<{ channel: string; status: string }> = [];

  for (const item of claimed) {
    // Email is intentionally not sent. Keep old queued email rows safely blocked.
    if (item.channel !== "sms") {
      await admin.from("guardian_delivery_logs").update({
        status: "blocked", provider: null, error_message: "email_notifications_disabled",
        updated_at: new Date().toISOString(),
      }).eq("id", item.id);
      results.push({ channel: item.channel, status: "blocked" });
      continue;
    }

    try {
      if (!phone) throw new Error("guardian_phone_missing");
      if (!normalizedPhone) throw new Error("invalid_bangladesh_mobile_number");
      if (!endpoint || !apiKey) {
        await admin.from("guardian_delivery_logs").update({
          status: "blocked", provider: "SMS gateway",
          processing_started_at: null,
          error_message: "sms_provider_not_configured",
          updated_at: new Date().toISOString(),
        }).eq("id", item.id);
        results.push({ channel: "sms", status: "blocked" });
        continue;
      }

      const date = String(attendance.record_data.date || new Date().toISOString().slice(0, 10));
      const studentName = String(studentData.name || "Student").slice(0, 80);
      const message = `CoachingOS: ${studentName} was marked Present on ${date}.`;
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ to: normalizedPhone, message, sender_id: senderId || undefined }),
        signal: AbortSignal.timeout(15000),
      });
      const responseText = await response.text();
      let responseData: Record<string, unknown> = {};
      try { responseData = JSON.parse(responseText); } catch { /* provider may return plain text */ }
      if (!response.ok || responseData.success === false || responseData.status === "error") {
        throw new Error(`sms_provider_error_${response.status}: ${safeError(responseText)}`);
      }

      const providerMessageId = String(responseData.message_id || responseData.messageId || responseData.id || "");
      await admin.from("guardian_delivery_logs").update({
        status: "sent", provider: "SMS gateway",
        provider_message_id: providerMessageId || null,
        provider_delivery_status: "accepted",
        processing_started_at: null,
        next_attempt_at: null,
        error_message: null, sent_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      }).eq("id", item.id);
      results.push({ channel: "sms", status: "provider_accepted" });
    } catch (error) {
      const message = error instanceof Error ? safeError(error.message) : "delivery_failed";
      await admin.from("guardian_delivery_logs").update({
        status: Number(item.attempt_count) < 3 ? "queued" : "failed",
        next_attempt_at: Number(item.attempt_count) < 3
          ? new Date(Date.now() + (Number(item.attempt_count) === 1 ? 60_000 : 5 * 60_000)).toISOString()
          : null,
        processing_started_at: null,
        error_message: message,
        updated_at: new Date().toISOString(),
      }).eq("id", item.id);
      results.push({ channel: "sms", status: "failed" });
    }
  }

  return json({
    ok: true,
    processed: results.length,
    results,
    note: "provider_accepted means the SMS provider accepted the request; handset delivery requires provider delivery receipts.",
  });
});
