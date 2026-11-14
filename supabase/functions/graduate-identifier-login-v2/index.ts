import { createClient } from "npm:@supabase/supabase-js@2";
const allowed="https://shahadatyofficial.github.io";
const cors={"Access-Control-Allow-Origin":allowed,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json; charset=utf-8"}});
const attempts=new Map<string,{count:number;reset:number}>();
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS"){const o=req.headers.get("origin");if(o&&o!==allowed)return new Response("Forbidden",{status:403});return new Response("ok",{headers:cors});}
 if(req.method!=="POST")return reply({error:"LOGIN_FAILED"},405);
 const o=req.headers.get("origin");if(o&&o!==allowed)return reply({error:"LOGIN_FAILED"},403);
 const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"",publishable=Deno.env.get("SUPABASE_PUBLISHABLE_KEY")||"",secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY")||"",api=req.headers.get("apikey")||"",clientKey=anon||publishable;
 if(!url||!clientKey||!secret||![anon,publishable].includes(api))return reply({error:"LOGIN_FAILED"},401);
 const ip=(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim().slice(0,80),now=Date.now(),a=attempts.get(ip);
 if(a&&a.reset>now&&a.count>=8)return reply({error:"LOGIN_FAILED"},429);
 if(!a||a.reset<=now)attempts.set(ip,{count:1,reset:now+600000});else a.count++;
 let b:any;try{const raw=await req.text();if(raw.length>3000)return reply({error:"LOGIN_FAILED"},400);b=JSON.parse(raw);}catch{return reply({error:"LOGIN_FAILED"},400);}
 const identifier=String(b.identifier||"").trim(),password=String(b.password||"");
 if(!identifier||identifier.length>150||!password||password.length>72)return reply({error:"LOGIN_FAILED"},401);
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:rows,error}=await admin.from("graduate_profiles").select("auth_user_id,full_name").not("auth_user_id","is",null).limit(5000);
 if(error||!rows)return reply({error:"LOGIN_FAILED"},401);
 const needle=identifier.toLocaleLowerCase("ar").replace(/\s+/g," ").trim();
 const matches=rows.filter((r:any)=>String(r.full_name||"").toLocaleLowerCase("ar").replace(/\s+/g," ").trim()===needle);
 if(matches.length!==1)return reply({error:"LOGIN_FAILED"},401);
 const {data:u,error:ue}=await admin.auth.admin.getUserById(matches[0].auth_user_id),email=String(u?.user?.email||"").trim().toLowerCase();
 if(ue||!email||u?.user?.app_metadata?.graduate_admin_approved!==true)return reply({error:"LOGIN_FAILED"},401);
 const auth=createClient(url,clientKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:session,error:loginErr}=await auth.auth.signInWithPassword({email,password});
 if(loginErr||!session.session)return reply({error:"LOGIN_FAILED"},401);
 return reply({access_token:session.session.access_token,refresh_token:session.session.refresh_token,token_type:session.session.token_type,expires_in:session.session.expires_in});
});