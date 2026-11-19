import { createClient } from "npm:@supabase/supabase-js@2";
const allowedOrigin="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowedOrigin,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
function normalizePhone(value:string){let d=value.replace(/[٠-٩۰-۹]/g,x=>String("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".indexOf(x)%10)).replace(/[^0-9]/g,"");if(d.startsWith("0020"))d=d.slice(2);if(d.startsWith("20"))d="0"+d.slice(2);if(d.length===10&&d.startsWith("1"))d="0"+d;return /^01[0125]\d{8}$/.test(d)?d:null;}
function temporaryPassword(){const a="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";const b=crypto.getRandomValues(new Uint8Array(28));return Array.from(b,x=>a[x%a.length]).join("")+"aA7!";}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"METHOD_NOT_ALLOWED"},405);
 const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return reply({error:"FORBIDDEN"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||Deno.env.get("SUPABASE_PUBLISHABLE_KEY")||"",secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"",token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"").trim();
 if(!url||!anon||!secret||!token)return reply({error:"UNAUTHORIZED"},401);
 const caller=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:user,error:userError}=await caller.auth.getUser(token);if(userError||!user)return reply({error:"UNAUTHORIZED"},401);
 let body:any;try{const raw=await req.text();if(raw.length>3000)return reply({error:"INVALID_REQUEST"},400);body=JSON.parse(raw);}catch{return reply({error:"INVALID_REQUEST"},400);}
 const certificateId=String(body.certificate_id||"").trim();if(!/^[0-9a-f-]{36}$/i.test(certificateId))return reply({error:"INVALID_REQUEST"},400);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:cert,error:certError}=await admin.from("certificates").select("id,institution_id,branch_id,trainee_id,student_name,student_phone,student_email,governorate,center,source_type,status").eq("id",certificateId).maybeSingle();
 if(certError||!cert)return reply({error:"CERTIFICATE_NOT_FOUND"},404);
 if(!cert.institution_id||cert.source_type!=="institution"||cert.status!=="active")return reply({error:"NOT_INSTITUTION_CERTIFICATE"},400);
 const {data:permitted,error:permissionError}=await caller.rpc("institution_has_permission",{p_institution_id:cert.institution_id,p_permission:"certificates.issue",p_branch_id:cert.branch_id||null});
 if(permissionError||permitted!==true)return reply({error:"FORBIDDEN"},403);
 const {data:institution,error:institutionError}=await admin.from("institutions").select("id,name,status").eq("id",cert.institution_id).maybeSingle();
 if(institutionError||!institution||institution.status!=="approved")return reply({error:"INSTITUTION_NOT_APPROVED"},403);
 let trainee:any=null;
 if(cert.trainee_id){const {data}=await admin.from("institution_trainees").select("id,full_name,phone,email,governorate").eq("id",cert.trainee_id).maybeSingle();trainee=data;}
 const mobile=normalizePhone(String(cert.student_phone||trainee?.phone||""));
 if(!mobile)return reply({success:false,account_created:false,reason:"PHONE_REQUIRED",message:"تم إصدار الشهادة، لكن لا يمكن إنشاء حساب الخريج دون رقم هاتف مصري صحيح."});
 const {data:existingRequests,error:requestCheck}=await admin.from("graduate_access_requests").select("id,account_origin,status").eq("phone",mobile).limit(1);
 if(requestCheck)return reply({error:"DUPLICATE_CHECK_FAILED"},500);
 const {data:existingProfiles,error:profileCheck}=await admin.from("graduate_profiles").select("id,account_origin").eq("phone",mobile).limit(1);
 if(profileCheck)return reply({error:"DUPLICATE_CHECK_FAILED"},500);
 if((existingRequests?.length||0)||(existingProfiles?.length||0))return reply({success:false,account_created:false,reason:"PHONE_ALREADY_LINKED",message:"تم إصدار الشهادة، لكن رقم الهاتف مرتبط بالفعل بحساب أو طلب خريج. يلزم مراجعة الإدارة لربط السجل دون إنشاء حساب مكرر."});
 const tempPassword=temporaryPassword(),email="graduate-"+crypto.randomUUID()+"@accounts.shahadaty.invalid",fullName=String(cert.student_name||trainee?.full_name||"").trim();
 const {data:created,error:createError}=await admin.auth.admin.createUser({email,password:tempPassword,email_confirm:true,app_metadata:{account_type:"graduate",graduate_admin_approved:false,account_origin:"institution",must_change_password:true},user_metadata:{full_name:fullName,phone:mobile,account_type:"graduate",account_origin:"institution",must_change_password:true,approval_status:"pending"}});
 if(createError||!created.user)return reply({error:"ACCOUNT_CREATE_FAILED",message:"تعذر إنشاء حساب الخريج. لم تتأثر الشهادة التي تم إصدارها."},500);
 const {error:insertError}=await admin.from("graduate_access_requests").insert({auth_user_id:created.user.id,full_name:fullName,email,phone:mobile,governorate:cert.governorate||trainee?.governorate||null,center:cert.center||institution.name||null,status:"pending",account_origin:"institution",institution_id:cert.institution_id,certificate_id:cert.id});
 if(insertError){await admin.auth.admin.deleteUser(created.user.id);if(insertError.code==="23505")return reply({success:false,account_created:false,reason:"REQUEST_EXISTS",message:"تم إصدار الشهادة، وطلب إنشاء حساب مرتبط بها موجود بالفعل."});return reply({error:"REQUEST_SAVE_FAILED",message:"تعذر حفظ طلب الحساب. لم تتأثر الشهادة التي تم إصدارها."},500);}
 return reply({success:true,account_created:true,status:"pending",phone:mobile,temporary_password:tempPassword,must_change_password:true,message:"تم إنشاء الحساب وطلب اعتماده. كلمة المرور المؤقتة تظهر مرة واحدة فقط؛ سلّمها للخريج عبر قناة خاصة، وسيُطلب منه تغييرها بعد أول دخول."});
});
