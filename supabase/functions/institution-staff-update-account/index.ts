import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://shahadatyofficial.github.io","http://localhost:3000","http://127.0.0.1:3000"]);
const cors = (origin:string) => ({
  "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://shahadatyofficial.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const reply = (origin:string,status:number,body:Record<string,unknown>) =>
  new Response(JSON.stringify(body),{status,headers:{...cors(origin),"Content-Type":"application/json; charset=utf-8"}});
const permissionKeys=["dashboard.view","branches.view","branches.manage","team.view","team.manage","trainees.view","trainees.manage","courses.view","courses.manage","certificates.view","certificates.issue","certificates.revoke","reports.view"];
const roles=["manager","training_manager","registrar","certificate_issuer","branch_manager","viewer"];

Deno.serve(async(req:Request)=>{
 const origin=req.headers.get("origin")||"";
 if(req.method==="OPTIONS"){if(origin&&!allowedOrigins.has(origin))return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors(origin)});}
 if(req.method!=="POST")return reply(origin,405,{error:"METHOD_NOT_ALLOWED"});
 if(origin&&!allowedOrigins.has(origin))return reply(origin,403,{error:"FORBIDDEN"});
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"";
 const secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"";
 const token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
 if(!url||!anon||!secret||!token)return reply(origin,401,{error:"UNAUTHORIZED"});
 const caller=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 let previousBranches:string[]=[];
 let oldProfile:any=null,oldRole:string|null=null,oldOverrides:any[]=[];
 let changedMemberId:string|null=null;
 try{
  const {data:authData,error:authError}=await caller.auth.getUser(token);
  if(authError||!authData.user)return reply(origin,401,{error:"UNAUTHORIZED"});
  const raw=await req.text();if(raw.length>12000)return reply(origin,400,{error:"INVALID_REQUEST"});
  let body:any;try{body=JSON.parse(raw);}catch{return reply(origin,400,{error:"INVALID_JSON"});}
  const institutionId=String(body?.institution_id||"").trim();
  const memberId=String(body?.institution_user_id||"").trim();
  const username=String(body?.username||"").trim().toLowerCase();
  const fullName=String(body?.full_name||"").trim();
  const password=String(body?.password||"");
  const role=String(body?.role||"").trim();
  const phone=String(body?.phone||"").trim()||null;
  const contactEmail=String(body?.contact_email||"").trim().toLowerCase()||null;
  const jobTitle=String(body?.job_title||"").trim()||null;
  const startDate=body?.employment_start_date?String(body.employment_start_date):null;
  const branchIds=Array.isArray(body?.branch_ids)?Array.from(new Set(body.branch_ids.map((v:unknown)=>String(v).trim()).filter(Boolean))):[];
  const hasPermissions=Array.isArray(body?.permissions);
  const permissions=hasPermissions?Array.from(new Set(body.permissions.map((v:unknown)=>String(v).trim()).filter(Boolean))):[];
  if(!/^[0-9a-f-]{36}$/i.test(institutionId)||!/^[0-9a-f-]{36}$/i.test(memberId)||
     !/^[a-z][a-z0-9._-]{2,29}$/.test(username)||fullName.length<2||fullName.length>160||
     (password&&(password.length<10||password.length>128))||!roles.includes(role)||
     branchIds.length>25||permissions.some((p:string)=>!permissionKeys.includes(p))||
     (contactEmail&&!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(contactEmail))||
     (startDate&&!/^\d{4}-\d{2}-\d{2}$/.test(startDate)))return reply(origin,400,{error:"INVALID_REQUEST"});
  const {data:canManage,error:permissionError}=await caller.rpc("institution_has_permission",{p_institution_id:institutionId,p_permission:"team.manage",p_branch_id:null});
  if(permissionError||canManage!==true)return reply(origin,403,{error:"TEAM_MANAGEMENT_FORBIDDEN"});
  const {data:callerMembership,error:callerError}=await admin.from("institution_users").select("id,role,status")
    .eq("institution_id",institutionId).eq("auth_user_id",authData.user.id).eq("status","active").maybeSingle();
  if(callerError||!callerMembership)return reply(origin,403,{error:"TEAM_MANAGEMENT_FORBIDDEN"});
  if(role==="manager"&&callerMembership.role!=="owner")return reply(origin,403,{error:"ONLY_OWNER_CAN_ASSIGN_MANAGER"});
  const {data:target,error:targetError}=await admin.from("institution_users").select("id,auth_user_id,role,status")
    .eq("id",memberId).eq("institution_id",institutionId).maybeSingle();
  if(targetError||!target||target.role==="owner"||target.auth_user_id===authData.user.id)return reply(origin,404,{error:"STAFF_MEMBER_NOT_FOUND"});
  const {data:targetAuth,error:targetAuthError}=await admin.auth.admin.getUserById(target.auth_user_id);
  if(targetAuthError||targetAuth.user?.app_metadata?.account_type!=="institution_staff"||
     targetAuth.user?.app_metadata?.institution_id!==institutionId)return reply(origin,403,{error:"STAFF_MEMBER_NOT_FOUND"});
  if(role!=="manager"&&!branchIds.length)return reply(origin,400,{error:"BRANCH_ASSIGNMENT_REQUIRED"});
  if(branchIds.length){
   const {data:validBranches,error}=await admin.from("institution_branches").select("id").eq("institution_id",institutionId).eq("is_active",true).in("id",branchIds);
   if(error||(validBranches||[]).length!==branchIds.length)return reply(origin,400,{error:"INVALID_BRANCH_ASSIGNMENT"});
  }
  const {data:duplicate}=await admin.from("institution_staff_profiles").select("id").eq("username",username).neq("institution_user_id",memberId).limit(1).maybeSingle();
  if(duplicate)return reply(origin,409,{error:"USERNAME_ALREADY_EXISTS"});
  const {data:profile,error:profileError}=await admin.from("institution_staff_profiles")
    .select("institution_user_id,username,full_name,phone,contact_email,job_title,employment_start_date")
    .eq("institution_user_id",memberId).eq("institution_id",institutionId).maybeSingle();
  if(profileError||!profile)return reply(origin,404,{error:"STAFF_PROFILE_NOT_FOUND"});
  oldProfile=profile;oldRole=target.role;changedMemberId=memberId;
  const {data:branchRows,error:branchError}=await admin.from("institution_user_branches").select("branch_id").eq("institution_user_id",memberId);
  if(branchError)throw new Error("BRANCH_READ_FAILED");previousBranches=(branchRows||[]).map((x:any)=>x.branch_id);
  const {data:overrideRows,error:overrideError}=await admin.from("institution_user_permission_overrides").select("permission_key,is_granted").eq("institution_user_id",memberId);
  if(overrideError)throw new Error("PERMISSION_READ_FAILED");oldOverrides=overrideRows||[];
  const {error:profileUpdateError}=await admin.from("institution_staff_profiles").update({
    username,full_name:fullName,phone,contact_email:contactEmail,job_title:jobTitle,employment_start_date:startDate
  }).eq("institution_user_id",memberId).eq("institution_id",institutionId);
  if(profileUpdateError)throw new Error("PROFILE_UPDATE_FAILED");
  const {error:roleUpdateError}=await admin.from("institution_users").update({role}).eq("id",memberId).eq("institution_id",institutionId);
  if(roleUpdateError)throw new Error("ROLE_UPDATE_FAILED");
  const {error:deleteBranchesError}=await admin.from("institution_user_branches").delete().eq("institution_user_id",memberId);
  if(deleteBranchesError)throw new Error("BRANCH_UPDATE_FAILED");
  if(branchIds.length){
   const {error:insertBranchesError}=await admin.from("institution_user_branches").insert(branchIds.map((branch_id:string)=>({institution_user_id:memberId,branch_id})));
   if(insertBranchesError)throw new Error("BRANCH_UPDATE_FAILED");
  }
  if(hasPermissions){
   const grants=new Set(permissions);
   if(grants.has("team.manage"))grants.add("team.view");
   if(grants.has("branches.manage"))grants.add("branches.view");
   if(grants.has("trainees.manage"))grants.add("trainees.view");
   if(grants.has("courses.manage"))grants.add("courses.view");
   if(grants.has("certificates.issue")||grants.has("certificates.revoke"))grants.add("certificates.view");
   const {error:clearError}=await admin.from("institution_user_permission_overrides").delete().eq("institution_user_id",memberId);
   if(clearError)throw new Error("PERMISSION_UPDATE_FAILED");
   const rows=permissionKeys.map(permission_key=>({institution_id:institutionId,institution_user_id:memberId,permission_key,is_granted:grants.has(permission_key)}));
   const {error:insertError}=await admin.from("institution_user_permission_overrides").insert(rows);
   if(insertError)throw new Error("PERMISSION_UPDATE_FAILED");
  }else if(role!==oldRole){
   const {error:clearError}=await admin.from("institution_user_permission_overrides").delete().eq("institution_user_id",memberId);
   if(clearError)throw new Error("PERMISSION_UPDATE_FAILED");
  }
  const authChanges:any={email:username+"@staff.shahadaty.invalid",email_confirm:true};
  if(password)authChanges.password=password;
  const {error:authUpdateError}=await admin.auth.admin.updateUserById(target.auth_user_id,authChanges);
  if(authUpdateError)throw new Error("AUTH_ACCOUNT_UPDATE_FAILED");
  return reply(origin,200,{success:true,username,role,password_updated:Boolean(password)});
 }catch(error){
  if(changedMemberId&&oldProfile&&oldRole){
   await admin.from("institution_staff_profiles").update(oldProfile).eq("institution_user_id",changedMemberId);
   await admin.from("institution_users").update({role:oldRole}).eq("id",changedMemberId);
   await admin.from("institution_user_branches").delete().eq("institution_user_id",changedMemberId);
   if(previousBranches.length)await admin.from("institution_user_branches").insert(previousBranches.map(branch_id=>({institution_user_id:changedMemberId,branch_id})));
   await admin.from("institution_user_permission_overrides").delete().eq("institution_user_id",changedMemberId);
   if(oldOverrides.length)await admin.from("institution_user_permission_overrides").insert(oldOverrides.map((x:any)=>({...x,institution_id:undefined,institution_user_id:changedMemberId})));
  }
  const message=error instanceof Error?error.message:"INTERNAL_ERROR";
  console.error("institution-staff-update-account:",message);
  return reply(origin,500,{error:message});
 }
});
