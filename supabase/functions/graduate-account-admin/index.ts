import { createClient } from "npm:@supabase/supabase-js@2";
const allowed="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowed,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
function phone(v:string){let d=v.replace(/[٠-٩۰-۹]/g,x=>String("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".indexOf(x)%10)).replace(/[^0-9]/g,"");if(d.startsWith("0020"))d=d.slice(2);if(d.startsWith("20"))d="0"+d.slice(2);if(d.length===10&&d.startsWith("1"))d="0"+d;return /^01[0125]\d{8}$/.test(d)?d:null;}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==allowed)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"METHOD_NOT_ALLOWED"},405);
 const o=req.headers.get("origin");if(o&&o!==allowed)return reply({error:"FORBIDDEN"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"",secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"",token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
 if(!url||!anon||!secret||!token)return reply({error:"UNAUTHORIZED"},401);
 const caller=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:callerData,error:callerErr}=await caller.auth.getUser(token);if(callerErr||!callerData.user)return reply({error:"UNAUTHORIZED"},401);
 const {data:isAdmin,error:adminErr}=await caller.rpc("is_platform_admin");if(adminErr||isAdmin!==true)return reply({error:"ADMIN_ONLY"},403);
 let b:any;try{const raw=await req.text();if(raw.length>5000)return reply({error:"INVALID_REQUEST"},400);b=JSON.parse(raw);}catch{return reply({error:"INVALID_REQUEST"},400);}
 const userId=String(b.user_id||""),action=String(b.action||"");
 if(!/^[0-9a-f-]{36}$/i.test(userId)||!["update","delete","reset_password"].includes(action))return reply({error:"INVALID_REQUEST"},400);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:reqRow}=await admin.from("graduate_access_requests").select("id,status,full_name,email,phone").eq("auth_user_id",userId).maybeSingle();
 if(!reqRow||reqRow.status!=="approved")return reply({error:"APPROVED_GRADUATE_ONLY"},404);
 if(action==="delete"){
  const {data:profile}=await admin.from("graduate_profiles").select("id,premium_photo_path,premium_cv_path").eq("auth_user_id",userId).maybeSingle();
  if(profile){
   const {data:alumni}=await admin.from("alumni_profiles").select("id").eq("legacy_graduate_profile_id",profile.id).maybeSingle();
   const goldPaths=[profile.premium_photo_path,profile.premium_cv_path].filter(Boolean);
   if(goldPaths.length){const {error}=await admin.storage.from("graduate-gold-private").remove(goldPaths);if(error)return reply({error:"GOLD_FILE_CLEANUP_FAILED"},500);}
   if(alumni){
    const {data:documents}=await admin.from("alumni_documents").select("storage_path").eq("alumni_id",alumni.id);
    const paths=(documents||[]).map((x:any)=>x.storage_path).filter(Boolean);
    if(paths.length){const {error}=await admin.storage.from("alumni-private").remove(paths);if(error)return reply({error:"FILE_CLEANUP_FAILED"},500);}
    const {error}=await admin.from("alumni_profiles").delete().eq("id",alumni.id);if(error)return reply({error:"PROFILE_CLEANUP_FAILED"},500);
   }
  }
  const {error}=await admin.auth.admin.deleteUser(userId);
  if(error)return reply({error:"DELETE_FAILED",message:error.message},500);
  return reply({success:true,action:"deleted"});
 }
 if(action==="reset_password"){
  const bytes=new Uint8Array(18);crypto.getRandomValues(bytes);
  const temporaryPassword=Array.from(bytes).map(x=>("0"+(x%36).toString(36)).slice(-1)).join("")+"Aa9!";
  const {error}=await admin.auth.admin.updateUserById(userId,{password:temporaryPassword});
  if(error)return reply({error:"RESET_FAILED",message:error.message},500);
  return reply({success:true,action:"reset_password",temporary_password:temporaryPassword,email:reqRow.email,phone:reqRow.phone,full_name:reqRow.full_name});
 }
 const fullName=String(b.full_name||"").trim(),email=String(b.email||"").trim().toLowerCase(),mobile=phone(String(b.phone||"")),governorate=String(b.governorate||"").trim(),center=String(b.center||"").trim();
 if(fullName.length<3||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||!mobile)return reply({error:"VALIDATION_FAILED"},400);
 const [{data:otherProfiles,error:profileCheckError},{data:otherRequests,error:requestCheckError}]=await Promise.all([
  admin.from("graduate_profiles").select("id").eq("phone",mobile).neq("auth_user_id",userId).limit(1),
  admin.from("graduate_access_requests").select("id").eq("phone",mobile).in("status",["pending","approved"]).neq("auth_user_id",userId).limit(1)
 ]);
 if(profileCheckError||requestCheckError)return reply({error:"DUPLICATE_CHECK_FAILED"},500);
 if((otherProfiles?.length||0)||(otherRequests?.length||0))return reply({error:"PHONE_ALREADY_USED"},409);
 const {error:authError}=await admin.auth.admin.updateUserById(userId,{email,email_confirm:true,user_metadata:{full_name:fullName,phone:mobile,governorate,center,account_type:"graduate",approval_status:"approved"}});
 if(authError)return reply({error:"ACCOUNT_UPDATE_FAILED",message:authError.message},500);
 const {error:profileError}=await admin.from("graduate_profiles").update({full_name:fullName,email,phone:mobile,governorate:governorate||null,center:center||null,profile_updated_at:new Date().toISOString()}).eq("auth_user_id",userId);
 if(profileError)return reply({error:"PROFILE_UPDATE_FAILED",message:profileError.message},500);
 const {error:requestError}=await admin.from("graduate_access_requests").update({full_name:fullName,email,phone:mobile,governorate:governorate||null,center:center||null,updated_at:new Date().toISOString()}).eq("auth_user_id",userId);
 if(requestError)return reply({error:"REQUEST_UPDATE_FAILED",message:requestError.message},500);
 return reply({success:true,action:"updated"});
});