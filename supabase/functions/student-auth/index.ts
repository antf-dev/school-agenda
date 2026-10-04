import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const url=Deno.env.get("SUPABASE_URL")!;
const secrets=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}");
const publishes=JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")||"{}");
const secretKey=secrets.default||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
const publishableKey=publishes.default||Deno.env.get("SUPABASE_ANON_KEY")||"";
const admin=createClient(url,secretKey,{auth:{autoRefreshToken:false,persistSession:false,detectSessionInUrl:false},global:{headers:{Authorization:`Bearer ${secretKey}`}}});
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const clean=(v:string,max=40)=>String(v||"").trim().replace(/\s+/g," ").slice(0,max);
const emailFor=(id:string)=>"student-"+id+"@accounts.school-agenda.local";
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({ok:false,message:"Method not allowed."},405);
 try{
  const body=await req.json(),action=String(body?.action||"");
  if(action==="set-password"){
   const token=String(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
   if(!token)return json({ok:false,message:"Authentication required."},401);
   const {data:userData,error:userError}=await admin.auth.getUser(token);
   if(userError||!userData.user)return json({ok:false,message:"Your student session is invalid."},401);
   const password=String(body?.password||"");
   if(password.length<8)return json({ok:false,message:"Password must be at least 8 characters."},400);
   const {data:student,error:studentError}=await admin.from("students").select("id").eq("id",userData.user.id).maybeSingle();
   if(studentError)throw studentError;if(!student)return json({ok:false,message:"Student profile not found."},404);
   const {error:updateError}=await admin.auth.admin.updateUserById(userData.user.id,{email:emailFor(userData.user.id),password,email_confirm:true});
   if(updateError)throw updateError;
   const {error:flagError}=await admin.from("students").update({has_password:true,updated_at:new Date().toISOString()}).eq("id",userData.user.id);
   if(flagError)throw flagError;
   return json({ok:true});
  }
  if(action==="login"){
   const name=clean(body?.name),className=clean(body?.className),password=String(body?.password||"");
   if(!name||!className||!password)return json({ok:false,message:"Enter your name, class and password."},400);
   const {data:candidates,error:candidateError}=await admin.from("students").select("id,name,class_name,class_key,has_password,is_admin,total_xp,level,created_at").ilike("name",name).eq("class_name",className).eq("has_password",true).limit(12);
   if(candidateError)throw candidateError;
   for(const candidate of candidates||[]){
    const response=await fetch(url+"/auth/v1/token?grant_type=password",{method:"POST",headers:{"apikey":publishableKey,"Content-Type":"application/json"},body:JSON.stringify({email:emailFor(candidate.id),password})});
    if(response.ok)return json({ok:true,session:await response.json(),profile:candidate});
   }
   return json({ok:false,message:"Name, class or password is incorrect."},401);
  }
  return json({ok:false,message:"Unknown account action."},400);
 }catch(error){console.error(error);return json({ok:false,message:"The account service could not complete that request."},500)}
});
