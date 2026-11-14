import { createClient } from "npm:@supabase/supabase-js@2";
const allowedOrigin="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowedOrigin,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"METHOD_NOT_ALLOWED"},405);
 const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return reply({error:"FORBIDDEN"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"",secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"",token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
 if(!url||!anon||!secret||!token)return reply({error:"UNAUTHORIZED"},401);
 const caller=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:userData,error:userErr}=await caller.auth.getUser(token);if(userErr||!userData.user)return reply({error:"UNAUTHORIZED"},401);
 const {data:isAdmin,error:adminErr}=await caller.rpc("is_platform_admin");if(adminErr||isAdmin!==true)return reply({error:"ADMIN_ONLY"},403);
 let b:any;try{const raw=await req.text();if(raw.length>4000)return reply({error:"INVALID_REQUEST"},400);b=JSON.parse(raw);}catch{return reply({error:"INVALID_REQUEST"},400);}
 const id=String(b.request_id||"").trim(),action=String(b.action||""),note=String(b.admin_note||"").trim().slice(0,1000);
 if(!/^[0-9a-f-]{36}$/i.test(id)||!["approve","reject"].includes(action))return reply({error:"INVALID_REQUEST"},400);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:r,error:readErr}=await admin.from("graduate_access_requests").select("*").eq("id",id).maybeSingle();
 if(readErr||!r)return reply({error:"REQUEST_NOT_FOUND"},404);
 if(r.status!=="pending")return reply({error:"REQUEST_ALREADY_REVIEWED",status:r.status},409);
 const now=new Date().toISOString();
 if(action==="reject"){
  const {error}=await admin.from("graduate_access_requests").update({status:"rejected",admin_note:note||"لم تتم الموافقة على الطلب.",reviewed_by:userData.user.id,reviewed_at:now,updated_at:now}).eq("id",id).eq("status","pending");
  if(error)return reply({error:"REVIEW_FAILED"},500);
  return reply({success:true,status:"rejected",email:r.email,full_name:r.full_name,phone:r.phone});
 }
 const profile={auth_user_id:r.auth_user_id,full_name:r.full_name,email:r.email,phone:r.phone,governorate:r.governorate,center:r.center};
 const {error:profileErr}=await admin.from("graduate_profiles").upsert(profile,{onConflict:"auth_user_id"});
 if(profileErr)return reply({error:"PROFILE_CREATE_FAILED",message:profileErr.message},500);
 const {data:target,error:targetErr}=await admin.auth.admin.getUserById(r.auth_user_id);
 if(targetErr||!target.user)return reply({error:"ACCOUNT_NOT_FOUND"},404);
 const appMeta={...(target.user.app_metadata||{}),graduate_admin_approved:true,graduate_approved_by:userData.user.id,graduate_approved_at:now};
 const {error:confirmErr}=await admin.auth.admin.updateUserById(r.auth_user_id,{email_confirm:true,app_metadata:appMeta,user_metadata:{...(target.user.user_metadata||{}),approval_status:"approved"}});
 if(confirmErr)return reply({error:"ACCOUNT_ACTIVATION_FAILED",message:confirmErr.message},500);
 const {error:updateErr}=await admin.from("graduate_access_requests").update({status:"approved",admin_note:note||null,reviewed_by:userData.user.id,reviewed_at:now,updated_at:now}).eq("id",id).eq("status","pending");
 if(updateErr)return reply({error:"REQUEST_UPDATE_FAILED"},500);
 return reply({success:true,status:"approved",email:r.email,full_name:r.full_name,phone:r.phone});
});