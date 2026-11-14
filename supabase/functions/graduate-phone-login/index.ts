import { createClient } from "npm:@supabase/supabase-js@2";
const allowedOrigin="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowedOrigin,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
function normalizePhone(value:string){let d=value.replace(/[٠-٩۰-۹]/g,x=>String("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".indexOf(x)%10)).replace(/[^0-9]/g,"");if(d.startsWith("0020"))d=d.slice(2);if(d.startsWith("20"))d="0"+d.slice(2);if(d.length===10&&d.startsWith("1"))d="0"+d;return /^01[0125]\d{8}$/.test(d)?d:null;}
const attempts=new Map<string,{count:number;reset:number}>();
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"LOGIN_FAILED"},405);
 const o=req.headers.get("origin");if(o&&o!==allowedOrigin)return reply({error:"LOGIN_FAILED"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"",publishable=Deno.env.get("SUPABASE_PUBLISHABLE_KEY")||"",secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"",api=req.headers.get("apikey")||"",clientKey=anon||publishable;
 if(!url||!clientKey||!secret||![anon,publishable].includes(api))return reply({error:"LOGIN_FAILED"},401);
 const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim().slice(0,80),now=Date.now(),a=attempts.get(ip);
 if(a&&a.reset>now&&a.count>=8)return reply({error:"LOGIN_FAILED"},429);
 if(!a||a.reset<=now)attempts.set(ip,{count:1,reset:now+600000});else a.count++;
 let b:any;try{const raw=await req.text();if(raw.length>3000)return reply({error:"LOGIN_FAILED"},400);b=JSON.parse(raw);}catch{return reply({error:"LOGIN_FAILED"},400);}
 const mobile=normalizePhone(String(b.phone||"")),password=String(b.password||"");
 if(!mobile||!password||password.length>72)return reply({error:"LOGIN_FAILED"},401);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:rows,error}=await admin.from("graduate_profiles").select("phone,auth_user_id").not("auth_user_id","is",null).eq("phone",mobile).limit(2);
 if(error||!rows||rows.length!==1)return reply({error:"LOGIN_FAILED"},401);
 const {data:userResult,error:userError}=await admin.auth.admin.getUserById(rows[0].auth_user_id),email=String(userResult?.user?.email||"").trim().toLowerCase();
 if(userError||!email||userResult?.user?.app_metadata?.graduate_admin_approved!==true)return reply({error:"LOGIN_FAILED"},401);
 const auth=createClient(url,clientKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:login,error:loginError}=await auth.auth.signInWithPassword({email,password});
 if(loginError||!login.session)return reply({error:"LOGIN_FAILED"},401);
 return reply({access_token:login.session.access_token,refresh_token:login.session.refresh_token,token_type:login.session.token_type,expires_in:login.session.expires_in});
});