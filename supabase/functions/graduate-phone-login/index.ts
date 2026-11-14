import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigin = "https://shahadatyofficial.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" } });
}
function normalizePhone(value: string): string | null {
  const map: Record<string,string> = {"٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9","۰":"0","۱":"1","۲":"2","۳":"3","۴":"4","۵":"5","۶":"6","۷":"7","۸":"8","۹":"9"};
  let d = value.replace(/[٠-٩۰-۹]/g, x => map[x]).replace(/[^0-9]/g, "");
  if (d.startsWith("0020")) d = d.slice(2);
  if (d.startsWith("20")) d = "0" + d.slice(2);
  if (d.length === 10 && d.startsWith("1")) d = "0" + d;
  return /^01[0125]\d{8}$/.test(d) ? d : null;
}
const attempts = new Map<string,{count:number;resetAt:number}>();
function rateLimited(ip:string) {
  const now=Date.now(), current=attempts.get(ip);
  if(!current||current.resetAt<=now){attempts.set(ip,{count:1,resetAt:now+10*60*1000});return false;}
  current.count++; return current.count>8;
}
Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS"){const origin=req.headers.get("origin");if(origin&&origin!==allowedOrigin)return new Response("Forbidden",{status:403});return new Response("ok",{headers:corsHeaders});}
  if(req.method!=="POST")return json({error:"LOGIN_FAILED"},405);
  const origin=req.headers.get("origin");if(origin&&origin!==allowedOrigin)return json({error:"LOGIN_FAILED"},403);
  const url=Deno.env.get("SUPABASE_URL");
  const anonKey=Deno.env.get("SUPABASE_ANON_KEY")||"";
  const publishableKey=Deno.env.get("SUPABASE_PUBLISHABLE_KEY")||"";
  const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||Deno.env.get("SUPABASE_SECRET_KEY");
  const suppliedKey=req.headers.get("apikey")||"";
  if(!url||!serviceKey||(!anonKey&&!publishableKey)||![anonKey,publishableKey].includes(suppliedKey))return json({error:"LOGIN_FAILED"},401);
  const ip=(req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim().slice(0,80);
  if(rateLimited(ip))return json({error:"LOGIN_FAILED"},429);
  let body:{phone?:string;password?:string};
  try{const raw=await req.text();if(raw.length>3000)return json({error:"LOGIN_FAILED"},400);body=JSON.parse(raw);}catch{return json({error:"LOGIN_FAILED"},400);}
  const phone=normalizePhone(String(body.phone||"")),password=String(body.password||"");
  if(!phone||!password||password.length>72)return json({error:"LOGIN_FAILED"},401);
  const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:rows,error:lookupError}=await admin.from("graduate_profiles").select("phone,auth_user_id").not("auth_user_id","is",null).limit(2000);
  if(lookupError||!rows)return json({error:"LOGIN_FAILED"},401);
  const matches=rows.filter((r:any)=>normalizePhone(String(r.phone||""))===phone&&r.auth_user_id);
  // Ambiguous phone numbers are never allowed to select an account.
  if(matches.length!==1)return json({error:"LOGIN_FAILED"},401);
  const {data:userResult,error:userError}=await admin.auth.admin.getUserById(matches[0].auth_user_id);
  const email=String(userResult?.user?.email||"").trim().toLowerCase();
  if(userError||!email)return json({error:"LOGIN_FAILED"},401);
  const key=anonKey||publishableKey;
  const auth=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:login,error:loginError}=await auth.auth.signInWithPassword({email,password});
  if(loginError||!login.session)return json({error:"LOGIN_FAILED"},401);
  return json({access_token:login.session.access_token,refresh_token:login.session.refresh_token,token_type:login.session.token_type,expires_in:login.session.expires_in});
});