import { createClient } from "npm:@supabase/supabase-js@2";
const allowed="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowed,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==allowed)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"METHOD_NOT_ALLOWED"},405);
 const o=req.headers.get("origin");if(o&&o!==allowed)return reply({error:"FORBIDDEN"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"",secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"",token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
 if(!url||!anon||!secret||!token)return reply({error:"UNAUTHORIZED"},401);
 const caller=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:userData,error:userErr}=await caller.auth.getUser(token);if(userErr||!userData.user)return reply({error:"UNAUTHORIZED"},401);
 let body:any;try{const raw=await req.text();if(raw.length>1000)return reply({error:"INVALID_REQUEST"},400);body=JSON.parse(raw);}catch{return reply({error:"INVALID_REQUEST"},400);}
 if(typeof body.consent!=="boolean")return reply({error:"INVALID_CONSENT"},400);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:p,error:pErr}=await admin.from("graduate_profiles").select("id,full_name,email,phone,governorate,center,bio,publication_consent").eq("auth_user_id",userData.user.id).maybeSingle();
 if(pErr||!p)return reply({error:"PROFILE_NOT_FOUND"},404);
 const {data:alumni,error:aErr}=await admin.from("alumni_profiles").select("id,visibility_status").eq("legacy_graduate_profile_id",p.id).maybeSingle();
 if(aErr)return reply({error:"PROFILE_SYNC_FAILED"},500);
 if(!alumni)return reply({success:true,listed:false});
 const visibility=!body.consent?"hidden":alumni.visibility_status==="paused"?"paused":"public";
 const {error:updateErr}=await admin.from("alumni_profiles").update({publication_consent:body.consent,publication_consent_at:body.consent?new Date().toISOString():null,visibility_status:visibility,full_name:p.full_name,phone:p.phone,email:p.email,governorate:p.governorate,center:p.center,professional_summary:p.bio,updated_at:new Date().toISOString()}).eq("id",alumni.id);
 if(updateErr)return reply({error:"PROFILE_SYNC_FAILED",message:updateErr.message},500);
 return reply({success:true,listed:visibility==="public",visibility_status:visibility});
});