import { createClient } from "npm:@supabase/supabase-js@2";
const allowedOrigin="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowedOrigin,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
function phone(value:string){let d=value.replace(/[٠-٩۰-۹]/g,x=>String("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".indexOf(x)%10)).replace(/[^0-9]/g,"");if(d.startsWith("0020"))d=d.slice(2);if(d.startsWith("20"))d="0"+d.slice(2);if(d.length===10&&d.startsWith("1"))d="0"+d;return /^01[0125]\d{8}$/.test(d)?d:null;}
const attempts=new Map<string,{count:number;reset:number}>();
function limited(key:string){const now=Date.now(),v=attempts.get(key);if(!v||v.reset<=now){attempts.set(key,{count:1,reset:now+600000});return false;}v.count++;return v.count>5;}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"METHOD_NOT_ALLOWED"},405);
 const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return reply({error:"FORBIDDEN"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"";
 if(!url||!key)return reply({error:"SERVER_CONFIGURATION"},500);
 let b:any;try{const raw=await req.text();if(raw.length>10000)return reply({error:"INVALID_REQUEST"},400);b=JSON.parse(raw);}catch{return reply({error:"INVALID_REQUEST"},400);}
 const fullName=String(b.full_name||"").trim(),email=String(b.email||"").trim().toLowerCase(),mobile=phone(String(b.phone||"")),password=String(b.password||""),governorate=String(b.governorate||"").trim(),center=String(b.center||"").trim();
 if(fullName.length<3||fullName.length>150||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254||!mobile||password.length<8||password.length>72)return reply({error:"VALIDATION_FAILED",message:"راجع الاسم والبريد ورقم الهاتف وكلمة المرور (8 أحرف على الأقل)."},400);
 const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim().slice(0,80);
 if(limited("ip:"+ip)||limited("phone:"+mobile)||limited("email:"+email))return reply({error:"RATE_LIMITED",message:"تم تجاوز عدد المحاولات. حاول مرة أخرى بعد عدة دقائق."},429);
 if(attempts.size>3000){const now=Date.now();for(const [k,v] of attempts)if(v.reset<=now)attempts.delete(k);}
 const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const [{data:requestRows,error:requestErr},{data:profileRows,error:profileErr}]=await Promise.all([
  admin.from("graduate_access_requests").select("id,status").eq("phone",mobile).limit(1),
  admin.from("graduate_profiles").select("id").eq("phone",mobile).limit(1)
 ]);
 if(requestErr||profileErr)return reply({error:"REQUEST_CHECK_FAILED"},500);
 if((requestRows?.length||0)>0||(profileRows?.length||0)>0)return reply({error:"PHONE_ALREADY_USED",message:"رقم الهاتف مرتبط بطلب أو حساب خريج بالفعل."},409);
 const {data:created,error:createError}=await admin.auth.admin.createUser({email,password,email_confirm:false,user_metadata:{full_name:fullName,phone:mobile,governorate,center,account_type:"graduate",approval_status:"pending"}});
 if(createError||!created.user)return reply({error:"ACCOUNT_CREATION_FAILED",message:"تعذر إنشاء الطلب. قد يكون البريد مسجلًا بالفعل."},409);
 const {error:insertError}=await admin.from("graduate_access_requests").insert({auth_user_id:created.user.id,full_name:fullName,email,phone:mobile,governorate:governorate||null,center:center||null,status:"pending"});
 if(insertError){await admin.auth.admin.deleteUser(created.user.id);return reply({error:"REQUEST_SAVE_FAILED",message:insertError.code==="23505"?"رقم الهاتف مرتبط بطلب آخر بالفعل.":"تعذر حفظ طلب العضوية. تحقق من البريد ورقم الهاتف."},409);}
 return reply({success:true,status:"pending",message:"تم استلام طلبك بنجاح. سيظهر للإدارة للمراجعة، وسيتم إبلاغك بعد الموافقة."});
});