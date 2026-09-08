import { createClient } from "npm:@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const norm=(v:unknown)=>String(v??"").trim().toLowerCase().replaceAll("-","_").replaceAll(" ","_");
const errorMessage=(value:unknown)=>{
  if(value instanceof Error)return value.message;
  if(value&&typeof value==="object"){
    const item=value as Record<string,unknown>;
    for(const key of ["message","msg","error_description","error","details","hint"]){
      const nested=item[key];
      if(typeof nested==="string"&&nested.trim())return nested;
      if(nested&&nested!==value){
        const text=errorMessage(nested);
        if(text&&text!=="Error desconocido")return text;
      }
    }
    try{return JSON.stringify(value);}catch(_){/* sin datos serializables */}
  }
  const text=String(value??"").trim();
  return text&&text!=="[object Object]"?text:"Error desconocido";
};
const expected:Record<string,string[]>={
  administracion:[],
  director_nacional:[],director_zona:["director_nacional"],
  jefe_ventas:["director_zona","director_nacional"],
  jefe_equipo:["jefe_ventas","director_zona","director_nacional"],
  agente:["jefe_equipo","jefe_ventas","director_zona","director_nacional"],
};
const passwordRedirect="https://safebrok-acceso-47f45.web.app/crear-password.html";

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  try{
    const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authorization=req.headers.get("Authorization")??"";
    const caller=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
    const {data:{user},error:userError}=await caller.auth.getUser();
    if(userError||!user)throw new Error("Sesión no válida");
    const admin=createClient(url,service,{auth:{persistSession:false}});
    const {data:actor}=await admin.from("usuarios").select("id,rol_usuario").eq("auth_id",user.id).single();
    if(!actor||!["administracion","director_nacional"].includes(norm(actor.rol_usuario)))throw new Error("Acción reservada a Administración");
    const body=await req.json();let action=String(body.action??"");
    let target:any=null;
    if(body.user_id){const r=await admin.from("usuarios").select("*").eq("id",body.user_id).single();if(r.error)throw r.error;target=r.data;}
    const validate=async(roleValue:unknown,parentId:unknown)=>{
      const role=norm(roleValue);if(!(role in expected))throw new Error("Rol no válido");
      const needed=expected[role];if(needed.length===0){if(parentId)throw new Error("Este rol no puede tener responsable");return null;}
      if(!parentId)throw new Error("Debes seleccionar el responsable directo");
      const {data:p}=await admin.from("usuarios").select("id,rol_usuario,estado").eq("id",parentId).single();
      if(!p||!needed.includes(norm(p.rol_usuario))||["bloqueado","inactivo","desactivado"].includes(norm(p.estado)))throw new Error("Responsable no válido para la jerarquía");
      return p.id;
    };
    if(action==="create"){
      const email=norm(body.email),role=norm(body.rol_usuario),parent=await validate(role,body.parent_id);
      if(!email.includes("@"))throw new Error("Email no válido");
      const exists=await admin.from("usuarios").select("id").ilike("email",email).maybeSingle();if(exists.data)throw new Error("Este email ya existe");
      let authUser:any=null;
      let authCreated=false;
      const invited=await admin.auth.admin.inviteUserByEmail(email,{
        redirectTo:passwordRedirect,
        data:{
          nombre:String(body.nombre??""),
          apellidos:String(body.apellidos??""),
          requires_password_setup:true,
        },
      });
      if(!invited.error&&invited.data.user){
        authUser=invited.data.user;
        authCreated=true;
      }else{
        const inviteMessage=errorMessage(invited.error).toLowerCase();
        if(!inviteMessage.includes("already")&&!inviteMessage.includes("registered")&&!inviteMessage.includes("exists")){
          throw invited.error??new Error("No se pudo crear Auth");
        }
        for(let page=1;page<=10&&!authUser;page++){
          const listed=await admin.auth.admin.listUsers({page,perPage:100});
          if(listed.error)throw listed.error;
          authUser=listed.data.users.find((item)=>norm(item.email)===email)??null;
          if(listed.data.users.length<100)break;
        }
        if(!authUser)throw new Error("El email existe en Auth pero no se pudo recuperar su cuenta");
        const linked=await admin.from("usuarios").select("id").eq("auth_id",authUser.id).maybeSingle();
        if(linked.data)throw new Error("La cuenta Auth ya está vinculada a otro usuario de SafeBrok");
      }
      const inserted=await admin.from("usuarios").insert({
        auth_id:authUser.id,
        nombre:String(body.nombre??"").trim(),
        apellidos:String(body.apellidos??"").trim(),
        email,
        rol_usuario:role,
        parent_id:parent,
        estado:"activo",
        direccion:String(body.direccion??"").trim(),
        numero_direccion:String(body.numero_direccion??"").trim(),
        codigo_postal:String(body.codigo_postal??"").trim(),
        provincia:String(body.provincia??"").trim(),
        localidad:String(body.localidad??"").trim(),
      }).select().single();
      if(inserted.error){if(authCreated)await admin.auth.admin.deleteUser(authUser.id);throw inserted.error;}
      target=inserted.data;
      if(!authCreated){
        const reset=await admin.auth.resetPasswordForEmail(email,{redirectTo:passwordRedirect});
        if(reset.error)console.error("Cuenta recuperada, pero no se pudo reenviar acceso",reset.error);
      }
      if(body.incorporacion_id){const link=await admin.from("incorporaciones").update({usuario_creado_id:target.id}).eq("id",body.incorporacion_id).eq("estado","ALTA_COMPLETADA").is("usuario_creado_id",null);if(link.error)throw link.error;}
    }else if(action==="update_assignment"){
      if(!target)throw new Error("Usuario no encontrado");const role=norm(body.rol_usuario),parent=await validate(role,body.parent_id);
      const currentRole=norm(target.rol_usuario);if(currentRole!==role){const open=await admin.from("cambios_rol").select("id").eq("usuario_id",target.id).not("estado","in","(APROBADO,CANCELADO,RECHAZADO)").maybeSingle();if(open.error)throw open.error;if(open.data)throw new Error("Este usuario ya tiene un cambio de rol contractual en curso");const created=await admin.from("cambios_rol").insert({usuario_id:target.id,candidato_auth_id:target.auth_id,rol_anterior:currentRole,rol_nuevo:role,parent_anterior_id:target.parent_id,parent_nuevo_id:parent,iniciado_por_usuario_id:actor.id,estado:"PENDIENTE_CONTRATO"}).select().single();if(created.error)throw created.error;target={...target,cambio_rol_id:created.data.id,rol_solicitado:role,parent_solicitado:parent};action="request_role_change";}else{const changed=await admin.from("usuarios").update({parent_id:parent}).eq("id",target.id).select().single();if(changed.error)throw changed.error;target=changed.data;}
    }else if(action==="deactivate"||action==="reactivate"){
      if(!target)throw new Error("Usuario no encontrado");if(target.auth_id===user.id)throw new Error("No puedes desactivar tu propia cuenta");
      const disabled=action==="deactivate";const auth=await admin.auth.admin.updateUserById(target.auth_id,{ban_duration:disabled?"876000h":"none"});if(auth.error)throw auth.error;
      const changed=await admin.from("usuarios").update({estado:disabled?"bloqueado":"activo"}).eq("id",target.id).select().single();if(changed.error)throw changed.error;target=changed.data;
    }else if(action==="resend_access"){
      if(!target)throw new Error("Usuario no encontrado");const reset=await admin.auth.resetPasswordForEmail(target.email,{redirectTo:passwordRedirect});if(reset.error)throw reset.error;
    }else throw new Error("Acción no reconocida");
    const log=await admin.from("usuarios_accesos_auditoria").insert({actor_usuario_id:actor.id,objetivo_usuario_id:target?.id,objetivo_email:target?.email,accion:action,detalle:{rol_usuario:target?.rol_usuario,parent_id:target?.parent_id}});
    if(log.error&&log.error.code!=="PGRST205"){
      console.error("No se pudo registrar la auditoría",log.error);
    }
    return new Response(JSON.stringify({ok:true}),{headers:{...cors,"Content-Type":"application/json"}});
  }catch(e){
    const message=errorMessage(e);
    console.error("gestionar-usuarios",message,e);
    return new Response(JSON.stringify({error:message}),{status:400,headers:{...cors,"Content-Type":"application/json"}});
  }
});
