import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const projectUrl = Deno.env.get("SUPABASE_URL") ?? "";
const readPublishableKey = () => {
  const raw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!raw) return "";
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed === "string") return parsed;
    if (parsed && typeof parsed === "object") return String(parsed.default || Object.values(parsed)[0] || "");
  } catch (_) {}
  return raw;
};
const publishableKey = readPublishableKey();
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const boundedText = (v: unknown, max: number) => String(v ?? "").trim().replace(/\s+/g, " ").slice(0, max);
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, message: "Method not allowed." }, 405);
  const token = String(req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!token || !projectUrl || !publishableKey) return json({ ok: false, message: "Sign in to use the study assistant." }, 401);
  try {
    const caller = createClient(projectUrl, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: auth, error: authError } = await caller.auth.getUser(token);
    if (authError || !auth.user) return json({ ok: false, message: "Your student session is invalid. Sign in again." }, 401);
    const body = await req.json();
    const question = boundedText(body?.question, 3000);
    if (!question) return json({ ok: false, message: "Enter a question." }, 400);
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) return json({ ok: false, message: "The study assistant is not activated yet. An administrator must add the OPENAI_API_KEY secret in Supabase Edge Function secrets." }, 503);
    const { data: quota, error: quotaError } = await caller.rpc("consume_student_ai_request");
    if (quotaError) return json({ ok: false, message: quotaError.message.includes("Daily study assistant limit") ? quotaError.message : "Could not authorize this study assistant request." }, quotaError.message.includes("Daily study assistant limit") ? 429 : 403);
    const submitted = Array.isArray(body?.context?.homework) ? body.context.homework.slice(0, 20).map((h: any) => ({
      subject: boundedText(h?.subject, 80), title: boundedText(h?.title, 180), dueDate: boundedText(h?.dueDate, 10),
    })) : [];
    const { data: student } = await caller.from("students").select("class_name").eq("id", auth.user.id).maybeSingle();
    if (!student) return json({ ok: false, message: "Student profile not found." }, 404);

    const crdpGrade = /^9/.test(String(student.class_name)) ? "Basic Education Grade 9" : /^10/.test(String(student.class_name)) ? "First Secondary" : "";
    const curriculumQuery = caller.from("curriculum_topics").select("crdp_grade,subject,unit,chapter,topic,learning_objective,source_url,source_version,source_page,mapping_status").order("subject").limit(80);
    const [posts, tests, plans, sessions, quizzes, curriculum] = await Promise.all([
      caller.from("class_agenda_posts").select("subject_name,title,type,due_date").not("due_date", "is", null).order("due_date").limit(20),
      caller.from("student_tests").select("subject,title,test_at").order("test_at").limit(20),
      caller.from("student_plan_items").select("subject,title,details,starts_at,duration_minutes,completed_at").order("starts_at").limit(20),
      caller.from("student_study_sessions").select("subject,topic,duration_minutes,started_at").not("ended_at", "is", null).order("started_at", { ascending: false }).limit(20),
      caller.from("student_quiz_attempts").select("score,weak_areas,completed_at,quiz_key").order("completed_at", { ascending: false }).limit(20),
      crdpGrade ? curriculumQuery.eq("crdp_grade", crdpGrade) : Promise.resolve({data:[],error:null}),
    ]);
    const queryErrors = [posts.error, tests.error, plans.error, sessions.error, quizzes.error, curriculum.error].filter(Boolean);
    if (queryErrors.length) return json({ ok: false, message: "Could not load the academic context for this request." }, 500);

    const context = {
      class: student.class_name,
      localHomework: submitted,
      classDeadlines: posts.data || [],
      tests: tests.data || [],
      studyPlan: plans.data || [],
      recentStudySessions: sessions.data || [],
      quizResultsAndWeakAreas: quizzes.data || [],
      verifiedCRDPCurriculum: curriculum.data || [],
      dailyRequestNumber: quota,
    };
    const model = Deno.env.get("OPENAI_MODEL") || "gpt-4o-mini";
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        temperature: 0.3,
        max_tokens: 1000,
        messages: [
          { role: "system", content: "You are a supportive study assistant for a school student. Use the supplied academic context to prioritize help. Treat verifiedCRDPCurriculum as the only authoritative curriculum data: never invent Lebanese CRDP topics, objectives, tracks, or citations. If the context lacks a verified topic, say it is unavailable and give clearly labeled general help. Keep explanations age-appropriate, concise, encouraging, and practical. Never claim to update homework, save a plan, record a quiz, or award XP. If making practice questions, include answers separately after the questions. Use only the student's supplied request and context; do not expose data belonging to other students. Context JSON: " + JSON.stringify(context) },
          { role: "user", content: question },
        ],
      }),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error("Study assistant provider error:", response.status, result?.error?.type || result?.error?.code || "unknown");
      return json({ ok: false, message: "The study assistant could not respond right now." }, 502);
    }
    const answer = boundedText(result?.choices?.[0]?.message?.content, 8000);
    if (!answer) return json({ ok: false, message: "The study assistant returned an empty response." }, 502);
    return json({ ok: true, answer });
  } catch (error) {
    console.error("Study assistant request failed:", error);
    return json({ ok: false, message: "The study assistant could not complete this request." }, 500);
  }
});
