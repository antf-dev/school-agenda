import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const url=Deno.env.get("SUPABASE_URL")!;
const readKey=(name:string,fallbackName:string)=>{const raw=Deno.env.get(name)||Deno.env.get(fallbackName)||"";if(!raw)return "";try{const parsed=JSON.parse(raw);if(typeof parsed==="string")return parsed;const values:string[]=[];const walk=(v:unknown)=>{if(typeof v==="string"){values.push(v);return}if(v&&typeof v==="object")Object.values(v as Record<string,unknown>).forEach(walk)};walk(parsed);return values.find(v=>v.startsWith("sb_secret_")||v.startsWith("sb_publishable_")||v.startsWith("eyJ"))||values[0]||""}catch(_){return raw}};
const secretKey=readKey("SUPABASE_SECRET_KEYS","SUPABASE_SERVICE_ROLE_KEY");
const publishableKey=readKey("SUPABASE_PUBLISHABLE_KEYS","SUPABASE_ANON_KEY");
const admin=createClient(url,secretKey,{auth:{autoRefreshToken:false,persistSession:false,detectSessionInUrl:false},global:{headers:{Authorization:`Bearer ${secretKey}`}}});
const authClient=createClient(url,publishableKey,{auth:{autoRefreshToken:false,persistSession:false,detectSessionInUrl:false}});
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const clean=(v:string,max=40)=>String(v||"").trim().replace(/\s+/g," ").slice(0,max);
const emailFor=(id:string)=>"student-"+id+"@accounts.school-agenda.local";
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS"){
  const requestedHeaders=req.headers.get("access-control-request-headers");
  return new Response("ok",{headers:{...cors,...(requestedHeaders?{"Access-Control-Allow-Headers":requestedHeaders}:{}),"Access-Control-Max-Age":"86400","Vary":"Origin, Access-Control-Request-Headers, Access-Control-Request-Method"}});
 }
 if(req.method!=="POST")return json({ok:false,message:"Method not allowed."},405);
 try{
  const body=await req.json(),action=String(body?.action||"");
  if(action==="remove-user"){
   const token=String(req.headers.get("Authorization")||"").replace(/^Bearer\\s+/i,"").trim();
   if(!token)return json({ok:false,message:"Authentication required."},401);
   const {data:actorData,error:actorError}=await authClient.auth.getUser(token);
   if(actorError||!actorData.user)return json({ok:false,message:"Your admin session is invalid. Sign in again."},401);
   const {data:actor,error:actorReadError}=await admin.from("students").select("is_admin").eq("id",actorData.user.id).maybeSingle();
   if(actorReadError)return json({ok:false,message:"Could not verify administrator access."},500);
   if(!actor?.is_admin)return json({ok:false,message:"Administrator access is required."},403);
   const targetId=String(body?.studentId||"").trim();
   if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(targetId))return json({ok:false,message:"Choose a valid student account."},400);
   if(targetId===actorData.user.id)return json({ok:false,message:"You cannot remove your own administrator account."},400);
   const {data:target,error:targetError}=await admin.from("students").select("id,name,is_admin").eq("id",targetId).maybeSingle();
   if(targetError)return json({ok:false,message:"Could not load the selected student."},500);
   if(!target)return json({ok:false,message:"This student account no longer exists."},404);
   if(target.is_admin)return json({ok:false,message:"Administrator accounts cannot be removed from the student directory."},403);

   const caller=createClient(url,publishableKey,{auth:{autoRefreshToken:false,persistSession:false,detectSessionInUrl:false},global:{headers:{Authorization:`Bearer ${token}`}}});
   const {data:ownedPaths,error:pathsError}=await caller.rpc("admin_list_student_image_paths",{p_student_id:targetId});
   if(pathsError)return json({ok:false,message:"Could not check the student's uploaded files; account was not removed."},500);
   const paths=(ownedPaths||[]).filter((path:unknown):path is string=>typeof path==="string"&&path.length>0);
   for(let offset=0;offset<paths.length;offset+=100){
    const {error:removeFilesError}=await admin.storage.from("class-agenda-images").remove(paths.slice(offset,offset+100));
    if(removeFilesError)return json({ok:false,message:"Could not remove the student's uploaded agenda images; account was not removed."},500);
   }
   const {error:deleteError}=await admin.auth.admin.deleteUser(targetId);
   if(deleteError)return json({ok:false,message:"Supabase could not remove this account: "+deleteError.message},500);
   return json({ok:true,name:String(target.name||"Student")});
  }
  if(action==="set-password"){
   const token=String(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
   if(!token)return json({ok:false,message:"Authentication required."},401);
   const {data:userData,error:userError}=await authClient.auth.getUser(token);
   if(userError||!userData.user)return json({ok:false,message:"Your student session is invalid."},401);
   const password=String(body?.password||"");
   if(password.length<8)return json({ok:false,message:"Password must be at least 8 characters."},400);
   const {data:student,error:studentError}=await admin.from("students").select("id").eq("id",userData.user.id).maybeSingle();
   if(studentError)return json({ok:false,message:"Could not read your student profile: "+studentError.message},500);
   if(!student)return json({ok:false,message:"Student profile not found."},404);
   const desiredEmail=emailFor(userData.user.id);
   const {data:authRow,error:authRowError}=await admin.auth.admin.getUserById(userData.user.id);
   if(authRowError)return json({ok:false,message:"Could not read your authentication account: "+authRowError.message},500);
   if(!authRow.user)return json({ok:false,message:"Authentication account not found."},404);
   if(authRow.user.email!==desiredEmail || authRow.user.is_anonymous){
    const {error:emailError}=await admin.auth.admin.updateUserById(userData.user.id,{email:desiredEmail,email_confirm:true});
    if(emailError)return json({ok:false,message:"Could not link the student account: "+emailError.message},500);
   }
   const {error:passwordError}=await admin.auth.admin.updateUserById(userData.user.id,{password});
   if(passwordError)return json({ok:false,message:"Could not set the password: "+passwordError.message},500);
   const {error:flagError}=await admin.from("students").update({has_password:true,updated_at:new Date().toISOString()}).eq("id",userData.user.id);
   if(flagError)return json({ok:false,message:"Could not save your account profile: "+flagError.message},500);
   return json({ok:true});
  }
  if(action==="login"){
   const name=clean(body?.name),className=clean(body?.className),password=String(body?.password||"");
   if(!name||!className||!password)return json({ok:false,message:"Enter your name, class and password."},400);
   const {data:candidates,error:candidateError}=await admin.from("students").select("id,name,class_name,class_key,has_password,is_admin,total_xp,level,created_at").ilike("name",name).eq("class_name",className).eq("has_password",true).limit(12);
   if(candidateError)return json({ok:false,message:"Could not load student accounts: "+candidateError.message},500);
   for(const candidate of candidates||[]){
    const response=await fetch(url+"/auth/v1/token?grant_type=password",{method:"POST",headers:{"apikey":publishableKey,"Content-Type":"application/json"},body:JSON.stringify({email:emailFor(candidate.id),password})});
    if(response.ok)return json({ok:true,session:await response.json(),profile:candidate});
   }
   return json({ok:false,message:"Name, class or password is incorrect."},401);
  }
  return json({ok:false,message:"Unknown account action."},400);
 }catch(error){console.error(error);return json({ok:false,message:"The account service could not complete that request."},500)}
});
