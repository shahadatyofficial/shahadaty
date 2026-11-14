import { createClient } from "npm:@supabase/supabase-js@2";
const originAllowed="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":originAllowed,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
function normPhone(v:string){let d=v.replace(/[٠-٩۰-۹]/g,x=>String("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".indexOf(x)%10)).replace(/[^0-9]/g,"");if(d.startsWith("0020"))d=d.slice(2);if(d.startsWith("20"))d="0"+d.slice(2);if(d.length===10&&d.startsWith("1"))d="0"+d;return /^01[0125]\d{8}$/.test(d)?d:null;}
const attempts=new Map<string,{n:number;until:number}>();
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==originAllowed)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"LOGIN_FAILED"},405);
 const o=req.headers.get("origin");if(o&&o!==originAllowed)return reply({error:"LOGIN_FAILED"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"",secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"",api=req.headers.get("apikey")||"";
 if(!url||!anon||!secret||api!==anon)return reply({error:"LOGIN_FAILED"},401);
 const ip=(req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim().slice(0,80),now=Date.now(),a=attempts.get(ip);
 if(a&&a.until>now&&a.n>=8)return reply({error:"LOGIN_FAILED"},429);
 if(!a||a.until<=now)attempts.set(ip,{n:1,until:now+600000});else a.n++;
 let b:any;try{const raw=await req.text();if(raw.length>3000)return reply({error:"LOGIN_FAILED"},400);b=JSON.parse(raw);}catch{return reply({error:"LOGIN_FAILED"},400);}
 const identifier=String(b.identifier||"").trim(),password=String(b.password||"");
 if(!identifier||!password||password.length>72)return reply({error:"LOGIN_FAILED"},401);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:rows,error}=await admin.from("graduate_profiles").select("auth_user_id,phone,full_name").not("auth_user_id","is",null).limit(5000);
 if(error||!rows)return reply({error:"LOGIN_FAILED"},401);
 const p=normPhone(identifier),needle=identifier.toLocaleLowerCase("ar").replace(/\s+/g," ").trim();
 const matches=rows.filter((r:any)=>p?normPhone(String(r.phone||""))===p:String(r.full_name||"").toLocaleLowerCase("ar").replace(/\s+/g," ").trim()===needle);
 if(matches.length!==1)return reply({error:"LOGIN_FAILED"},401);
 const {data:u,error:ue}=await admin.auth.admin.getUserById(matches[0].auth_user_id),email=String(u?.user?.email||"").trim().toLowerCase();
 if(ue||!email||!u?.user?.email_confirmed_at)return reply({error:"LOGIN_FAILED"},401);
 const auth=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:session,error:loginErr}=await auth.auth.signInWithPassword({email,password});
 if(loginErr||!session.session)return reply({error:"LOGIN_FAILED"},401);
 return reply({access_token:session.session.access_token,refresh_token:session.session.refresh_token,token_type:session.session.token_type,expires_in:session.session.expires_in});
});