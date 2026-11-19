import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

// Free-only mode: never contact an SMS gateway or consume provider credits.
Deno.serve((req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  return json({
    ok: true,
    disabled: true,
    processed: 0,
    message: "SMS delivery is disabled in this free-only setup. No SMS provider was contacted.",
  });
});
