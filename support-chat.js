/* Shahadaty live support chat — uses the page's existing Supabase client. */
(function(){
  if(!window.sb || document.getElementById('sh-chat-root')) return;
  const PHONE='20123333805';
  const EMAIL='shahadatyofficial@gmail.com';
  const TOKEN_KEY='shahadaty_support_chat_token_v1';
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const time=s=>{try{return new Date(s).toLocaleTimeString('ar-EG',{hour:'2-digit',minute:'2-digit'});}catch(_){return '';}};
  let token=localStorage.getItem(TOKEN_KEY)||'';
  let knownIds=new Set(),poller=null,loading=false,started=false;
  const root=document.createElement('div');root.id='sh-chat-root';
  root.innerHTML=`
    <div id="sh-chat-panel" role="dialog" aria-label="محادثة الدعم المباشر">
      <div class="sh-chat-head"><div class="sh-chat-avatar">💬</div><div class="sh-chat-head-main"><div class="sh-chat-head-title">فريق شهادتي العلمية</div><div class="sh-chat-head-sub">الدعم والمساعدة المباشرة</div></div><button class="sh-chat-close" type="button" aria-label="إغلاق">×</button></div>
      <div class="sh-chat-body" id="sh-chat-body">
        <div id="sh-chat-welcome">
          <div class="sh-chat-welcome">أهلاً بيك في شهادتي العلمية 👋<br>اكتب رسالتك وسيقوم فريق الدعم بمتابعتها والرد عليك هنا.</div>
          <form class="sh-chat-form" id="sh-chat-start-form">
            <input class="sh-chat-input" id="sh-chat-name" maxlength="100" placeholder="اسمك (اختياري)">
            <input class="sh-chat-input" id="sh-chat-email" maxlength="254" type="email" placeholder="البريد الإلكتروني (اختياري)">
            <textarea class="sh-chat-input" id="sh-chat-first-message" maxlength="2000" rows="3" required placeholder="اكتب رسالتك هنا..."></textarea>
            <button class="sh-chat-send" id="sh-chat-start-btn">ابدأ المحادثة</button>
          </form>
        </div>
        <div class="sh-chat-messages" id="sh-chat-messages" style="display:none"></div>
        <div id="sh-chat-closed" style="display:none;background:#fff;border-radius:12px;padding:12px;text-align:center;font-size:12px;color:#64748b">تم إغلاق هذه المحادثة. يمكنك بدء محادثة جديدة من خلال زر الدعم.</div>
      </div>
      <div class="sh-chat-compose" id="sh-chat-compose" style="display:none"><textarea id="sh-chat-text" maxlength="2000" rows="1" placeholder="اكتب رسالتك..."></textarea><button id="sh-chat-send-btn" type="button" aria-label="إرسال">➤</button></div>
      <div class="sh-chat-links"><a href="https://wa.me/${PHONE}" target="_blank" rel="noopener">واتساب</a><a href="mailto:${EMAIL}">البريد الإلكتروني</a></div>
    </div>
    <button id="sh-chat-launch" type="button" aria-label="افتح المحادثة المباشرة" aria-expanded="false"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5 9 9 0 0 1-4-.9L3 21l1.9-5.5a9 9 0 0 1-.9-4A8.5 8.5 0 0 1 12.5 3h.5a8.5 8.5 0 0 1 8 8v.5Z"/><path d="M8 12h.01M12 12h.01M16 12h.01"/></svg></button>`;
  document.body.appendChild(root);
  const toast=document.createElement('div');toast.id='sh-chat-toast';toast.textContent='وصلتك رسالة جديدة من فريق شهادتي';document.body.appendChild(toast);
  const panel=root.querySelector('#sh-chat-panel'),launch=root.querySelector('#sh-chat-launch'),body=root.querySelector('#sh-chat-body');
  const welcome=root.querySelector('#sh-chat-welcome'),messages=root.querySelector('#sh-chat-messages'),compose=root.querySelector('#sh-chat-compose');
  function notify(){toast.classList.add('show');setTimeout(()=>toast.classList.remove('show'),5000);}
  function showMessages(rows,initial=false){
    const ordered=(rows||[]).slice().reverse();
    const fresh=ordered.filter(m=>!knownIds.has(m.id));
    if(!initial&&fresh.some(m=>m.sender_role==='admin'))notify();
    ordered.forEach(m=>knownIds.add(m.id));
    messages.innerHTML=ordered.map(m=>'<div class="sh-chat-msg '+(m.sender_role==='visitor'?'visitor':'admin')+'">'+esc(m.body)+'<div class="sh-chat-time">'+time(m.created_at)+'</div></div>').join('');
    messages.style.display='flex';welcome.style.display='none';compose.style.display='flex';
    body.scrollTop=body.scrollHeight;
  }
  async function refresh(initial=false){
    if(!token||loading)return;loading=true;
    const{data,error}=await sb.rpc('support_chat_messages',{p_token:token});
    loading=false;
    if(error){if(String(error.message||'').includes('CHAT_NOT_FOUND')){localStorage.removeItem(TOKEN_KEY);token='';welcome.style.display='block';messages.style.display='none';compose.style.display='none';}return;}
    showMessages(data||[],initial);
  }
  async function startChat(event){
    event.preventDefault();const btn=root.querySelector('#sh-chat-start-btn'),msg=root.querySelector('#sh-chat-first-message').value.trim();
    if(!msg)return;
    btn.disabled=true;btn.textContent='جارٍ الإرسال...';
    if(!token){const bytes=new Uint8Array(32);crypto.getRandomValues(bytes);token=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');}
    const{data,error}=await sb.rpc('support_chat_start',{p_token:token,p_name:root.querySelector('#sh-chat-name').value.trim()||null,p_email:root.querySelector('#sh-chat-email').value.trim()||null,p_message:msg});
    btn.disabled=false;btn.textContent='ابدأ المحادثة';
    if(error){alert('تعذر بدء المحادثة حالياً. حاول مرة أخرى بعد قليل.');return;}
    localStorage.setItem(TOKEN_KEY,token);root.querySelector('#sh-chat-first-message').value='';started=true;await refresh(true);startPolling();
  }
  async function sendMessage(){
    const input=root.querySelector('#sh-chat-text'),btn=root.querySelector('#sh-chat-send-btn'),value=input.value.trim();
    if(!value||!token||btn.disabled)return;btn.disabled=true;
    const{error}=await sb.rpc('support_chat_send',{p_token:token,p_message:value});
    btn.disabled=false;
    if(error){alert(error.message==='CHAT_CLOSED'?'المحادثة مغلقة.':'تعذر إرسال الرسالة. حاول مرة أخرى.');return;}
    input.value='';await refresh(true);
  }
  function startPolling(){if(poller)clearInterval(poller);poller=setInterval(()=>refresh(false),4500);}
  launch.addEventListener('click',async()=>{
    const open=panel.classList.toggle('open');launch.setAttribute('aria-expanded',String(open));
    if(open){if(token)await refresh(true);else welcome.style.display='block';startPolling();}
  });
  root.querySelector('.sh-chat-close').addEventListener('click',()=>{panel.classList.remove('open');launch.setAttribute('aria-expanded','false');});
  root.querySelector('#sh-chat-start-form').addEventListener('submit',startChat);
  root.querySelector('#sh-chat-send-btn').addEventListener('click',sendMessage);
  root.querySelector('#sh-chat-text').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();sendMessage();}});
  toast.addEventListener('click',()=>{panel.classList.add('open');launch.setAttribute('aria-expanded','true');toast.classList.remove('show');refresh(false);});
  if(token){welcome.style.display='none';refresh(true);startPolling();}
})();