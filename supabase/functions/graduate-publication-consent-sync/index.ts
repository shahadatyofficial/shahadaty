import { createClient } from "npm:@supabase/supabase-js@2";
const allowed="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowed,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
const split=(v:string)=>Array.from(new Set(v.split(/[,،;؛\n]+/).map(x=>x.trim()).filter(x=>x.length>1&&x.length<=120))).slice(0,40);
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
 const {data:p,error:pErr}=await admin.from("graduate_profiles").select("id,auth_user_id,full_name,email,phone,governorate,center,bio,qualification,education_institution,specialization,graduation_year,work_experience,experience_years,professional_skills,languages,target_roles,portfolio_url,publication_consent").eq("auth_user_id",userData.user.id).maybeSingle();
 if(pErr||!p)return reply({error:"PROFILE_NOT_FOUND"},404);
 if(p.publication_consent!==body.consent)return reply({error:"CONSENT_STATE_MISMATCH"},409);
 const {data:existing,error:findErr}=await admin.from("alumni_profiles").select("id").eq("legacy_graduate_profile_id",p.id).maybeSingle();
 if(findErr)return reply({error:"PROFILE_SYNC_FAILED"},500);
 if(!body.consent){
  if(existing){const {error}=await admin.from("alumni_profiles").update({publication_consent:false,publication_consent_at:null,visibility_status:"hidden",updated_by:userData.user.id,updated_at:new Date().toISOString()}).eq("id",existing.id);if(error)return reply({error:"PROFILE_SYNC_FAILED"},500);}
  return reply({success:true,listed:false,visibility_status:"hidden"});
 }
 const now=new Date().toISOString();
 const summary=[p.bio,p.work_experience,p.experience_years?("سنوات الخبرة: "+p.experience_years):"",p.professional_skills?("المهارات: "+p.professional_skills):"",p.languages?("اللغات: "+p.languages):"",p.target_roles?("الوظائف المستهدفة: "+p.target_roles):"",p.portfolio_url?("معرض الأعمال: "+p.portfolio_url):""].filter(Boolean).join("\n\n").slice(0,12000);
 const profileNumber="GRAD-"+p.id.replace(/-/g,"").slice(0,16).toUpperCase();
 const {data:alumni,error:upsertErr}=await admin.from("alumni_profiles").upsert({profile_number:profileNumber,full_name:p.full_name||"خريج شهادتي",phone:p.phone,email:p.email,governorate:p.governorate,center:p.center,professional_summary:summary||null,visibility_status:"public",contact_sharing_requires_approval:true,legacy_graduate_profile_id:p.id,created_by:userData.user.id,updated_by:userData.user.id,publication_consent:true,publication_consent_at:now,updated_at:now},{onConflict:"legacy_graduate_profile_id"}).select("id").single();
 if(upsertErr||!alumni)return reply({error:"PROFILE_SYNC_FAILED",message:upsertErr?.message},500);
 const hasQualification=!!(p.qualification||p.education_institution||p.specialization||p.graduation_year);
 if(hasQualification){
  const qualificationName=[p.qualification,p.specialization].filter(Boolean).join(" - ")||"مؤهل علمي";
  const {data:oldQ}=await admin.from("alumni_qualifications").select("id").eq("alumni_id",alumni.id).is("certificate_id",null).eq("verification_status","unverified").order("created_at",{ascending:true}).limit(1).maybeSingle();
  const q={qualification_name:qualificationName,institution_name:p.education_institution||null,specialization:p.specialization||null,graduation_year:p.graduation_year||null,verification_status:"unverified",sort_order:0};
  const result=oldQ?await admin.from("alumni_qualifications").update(q).eq("id",oldQ.id):await admin.from("alumni_qualifications").insert({...q,alumni_id:alumni.id});
  if(result.error)return reply({error:"QUALIFICATION_SYNC_FAILED"},500);
 }
 const skillGroups=[["graduate_profile",split(p.professional_skills||"")],["graduate_language",split(p.languages||"")],["graduate_target_role",split(p.target_roles||"")]];
 for(const [category,values] of skillGroups){
  const {error:deleteError}=await admin.from("alumni_skills").delete().eq("alumni_id",alumni.id).eq("skill_category",category);
  if(deleteError)return reply({error:"SKILLS_SYNC_FAILED"},500);
  if(values.length){const {error:insertError}=await admin.from("alumni_skills").insert(values.map(skill_name=>({alumni_id:alumni.id,skill_name,skill_category:category})));if(insertError)return reply({error:"SKILLS_SYNC_FAILED"},500);}
 }
 return reply({success:true,listed:true,visibility_status:"public",alumni_profile_id:alumni.id});
});