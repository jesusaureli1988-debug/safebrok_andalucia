const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const escapeForScript = (value: string) =>
  JSON.stringify(value).replaceAll("<", "\\u003c");

Deno.serve((request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  const html = `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Crear contraseña · SafeBrok</title>
  <style>
    *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:linear-gradient(135deg,#06111b,#0b3546);font-family:Arial,sans-serif;color:#fff}
    .card{width:min(100%,480px);padding:34px;border:1px solid rgba(255,255,255,.14);border-radius:24px;background:rgba(10,30,43,.94);box-shadow:0 24px 70px rgba(0,0,0,.35)}
    .brand{color:#35d6e8;font-size:14px;font-weight:800;letter-spacing:1.5px}.title{margin:12px 0 8px;font-size:30px}.help{margin:0 0 26px;color:#bed0db;line-height:1.5}
    label{display:block;margin:17px 0 7px;font-weight:700}input{width:100%;padding:14px 15px;border:1px solid #55717f;border-radius:12px;background:#102b39;color:#fff;font-size:16px;outline:none}input:focus{border-color:#35d6e8}
    button{width:100%;margin-top:24px;padding:15px;border:0;border-radius:12px;background:#168add;color:#fff;font-size:16px;font-weight:800;cursor:pointer}button:disabled{opacity:.55;cursor:wait}
    .message{display:none;margin-top:20px;padding:14px;border-radius:12px;line-height:1.45}.error{display:block;background:#5b1f29;color:#ffd9df}.success{display:block;background:#0c574d;color:#dcfff8}.expired{display:block;background:#5d4315;color:#fff0c2}
  </style>
</head>
<body>
  <main class="card">
    <div class="brand">SAFEBROK</div>
    <h1 class="title">Crea tu contraseña</h1>
    <p class="help">Escribe la contraseña que utilizarás para acceder a SafeBrok. Debe tener al menos 8 caracteres.</p>
    <form id="form">
      <label for="password">Nueva contraseña</label>
      <input id="password" type="password" minlength="8" autocomplete="new-password" required>
      <label for="confirm">Repite la contraseña</label>
      <input id="confirm" type="password" minlength="8" autocomplete="new-password" required>
      <button id="submit" type="submit">Guardar contraseña</button>
    </form>
    <div id="message" class="message"></div>
  </main>
  <script>
    const SUPABASE_URL=${escapeForScript(supabaseUrl)};
    const ANON_KEY=${escapeForScript(anonKey)};
    const params=new URLSearchParams(location.hash.slice(1));
    const accessToken=params.get('access_token');
    const errorDescription=params.get('error_description');
    const form=document.getElementById('form');
    const message=document.getElementById('message');
    const submit=document.getElementById('submit');
    const show=(text,type)=>{message.textContent=text;message.className='message '+type};
    if(errorDescription||!accessToken){
      form.style.display='none';
      show(errorDescription?decodeURIComponent(errorDescription.replaceAll('+',' ')):'Este enlace no es válido o ha caducado. Solicita que te reenvíen el acceso desde SafeBrok.','expired');
    }
    form.addEventListener('submit',async(event)=>{
      event.preventDefault();
      const password=document.getElementById('password').value;
      const confirm=document.getElementById('confirm').value;
      if(password.length<8){show('La contraseña debe tener al menos 8 caracteres.','error');return}
      if(password!==confirm){show('Las contraseñas no coinciden.','error');return}
      submit.disabled=true;submit.textContent='Guardando…';message.className='message';
      try{
        const response=await fetch(SUPABASE_URL+'/auth/v1/user',{
          method:'PUT',headers:{'Content-Type':'application/json','apikey':ANON_KEY,'Authorization':'Bearer '+accessToken},
          body:JSON.stringify({password,data:{requires_password_setup:false}})
        });
        const data=await response.json().catch(()=>({}));
        if(!response.ok)throw new Error(data.msg||data.message||data.error_description||'No se pudo guardar la contraseña.');
        form.style.display='none';
        show('Contraseña creada correctamente. Ya puedes cerrar esta página y entrar en la aplicación SafeBrok con tu email y tu nueva contraseña.','success');
        history.replaceState(null,'',location.pathname);
      }catch(error){
        show(error instanceof Error?error.message:'No se pudo guardar la contraseña. Solicita un nuevo enlace.','error');
        submit.disabled=false;submit.textContent='Guardar contraseña';
      }
    });
  </script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      ...cors,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    },
  });
});
