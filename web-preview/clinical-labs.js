(function(root) {
  'use strict';
  const dateKey = date => [date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
  const stamp = value => new Intl.DateTimeFormat('es-GT',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value));
  const fold = value => value.trim().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/-/g,'');
  class HospitalClinicalLabsDesign {
    static states = ['Pendiente','En Proceso','Completado'];
    static exams = [{id:'urine',name:'Examen general de orina',category:'Orina'},{id:'stool',name:'Examen general de heces',category:'Heces'},{id:'blood',name:'Biometría hemática',category:'Sangre'},{id:'glucose',name:'Glucosa en sangre',category:'Sangre'},{id:'lipids',name:'Perfil lipídico',category:'Sangre'},{id:'parasites',name:'Examen de parásitos',category:'Heces'},{id:'antigen',name:'Prueba rápida de antígeno',category:'Otros'}];
    constructor(ui) { this.ui = ui; this.reset(); }
    reset() {
      this.doctorName = 'Dr. Luis Ramírez'; this.clinicName = 'Sede Central · Medicina interna'; this.ownPatientID = 'p1';
      this.patients = [
        {id:'p1',givenName:'María',familyName:'López',email:'maria.lopez@ejemplo.test',age:67,dui:'0123-45678',phone:'7123-4567',record:'DEMO-101',consultationTurn:'A-014'},
        {id:'p2',givenName:'Carlos',familyName:'Mendoza',email:'carlos.mendoza@ejemplo.test',age:42,dui:'0234-56789',phone:'7234-5678',record:'DEMO-102',consultationTurn:'A-015'},
        {id:'p3',givenName:'Ana',familyName:'Reyes',email:'ana.reyes@ejemplo.test',age:28,dui:'0345-67890',phone:'7345-6789',record:'DEMO-103',consultationTurn:'A-016'}];
      this.patientFilterDate=false;this.patientDate=dateKey(new Date());
      this.visits=[['p1','doctor-demo',0,'Consulta de seguimiento','Seguimiento registrado en el ejemplo.','Finalizada'],['p1','doctor-demo',-7,'Revisión de resultados','Resultados revisados en el ejemplo.','Finalizada'],['p2','doctor-demo',0,'Consulta general','Valoración registrada en el ejemplo.','En curso'],['p3','doctor-demo',1,'Primera consulta','Pendiente de atención.','Programada'],['p1','otro-doctor',0,'Consulta ajena que debe excluirse','No mostrar','Finalizada']].map(([patientID,doctorID,offset,reason,plan,status])=>{const day=new Date();day.setHours(9,0,0,0);day.setDate(day.getDate()+offset);return{id:root.crypto.randomUUID(),patientID,doctorID,date:day.toISOString(),reason,plan,status};});
      this.entries=[]; this.modal='';this.activeLabID=null;this.labReturnModal='record'; this.weight=''; this.height=''; this.requestDate=new Date().toISOString();this.activeDoctorID='doctor-demo';this.entryKind='Observación';this.entryText='';this.medication='';this.rxDetails={dose:'',unit:'',frequency:'',route:'',duration:'',quantity:''};this.linkedRequest=null;
      this.selected = ''; this.query = ''; this.preparing = false; this.exam = ''; this.observation = ''; this.confirmation = ''; this.category = 'Todos'; this.filterDate = false; this.date = dateKey(new Date());
      this.requests = HospitalClinicalLabsDesign.states.map((state,index) => {
        const day = new Date(); if(index === 2) day.setDate(day.getDate()-1);
        return {id:root.crypto.randomUUID(),patient:{...this.patients[0]},exam:{...HospitalClinicalLabsDesign.exams[index]},observation:'Observación clínica de ejemplo registrada en consulta.',doctorName:this.doctorName,clinicName:this.clinicName,requestedAt:day.toISOString(),consultationTurn:this.patients[0].consultationTurn,state,resultValues:state === 'Completado' ? [{name:'Hemoglobina de ejemplo',value:'13.2',unit:'g/dL',reference:'12–16 (ilustrativo)'}] : [],releasedAt:state === 'Completado' ? day.toISOString() : null,result:state === 'Completado' ? 'Resultado de ejemplo disponible. Sin documento clínico real.' : null};
      });
    }
    patient(role) { return this.patients.find(item => item.id === (role === 'doctor' ? this.selected : this.ownPatientID)); }
    fullName(patient) { return patient.givenName+' '+patient.familyName; }
    select(id) { this.modal='';this.weight='';this.height=''; this.selected = id; this.preparing = false; this.exam = ''; this.observation = ''; this.confirmation = ''; this.category = 'Todos'; this.filterDate = false; }
    canSubmit(role) {
      const patient = this.patient(role);
      return role === 'doctor' && this.preparing && patient && Number.isInteger(patient.age) && patient.age >= 0 && ['givenName','familyName','email','dui','phone','record','consultationTurn'].every(key => typeof patient[key] === 'string' && patient[key].trim())
        && HospitalClinicalLabsDesign.exams.some(exam => exam.id === this.exam) && !!this.observation.trim() && this.observation.length <= 2000 && !!this.doctorName.trim() && !!this.clinicName.trim() && this.measure(this.weight,.1,500)!==null && this.measure(this.height,20,250)!==null;
    }
    submit(role) {
      if (!this.canSubmit(role)) return false;
      const patient = this.patient(role), exam = HospitalClinicalLabsDesign.exams.find(item => item.id === this.exam);
      this.requests.unshift({id:root.crypto.randomUUID(),patient:{...patient},exam:{...exam},observation:this.observation.trim(),doctorName:this.doctorName,clinicName:this.clinicName,requestedAt:this.requestDate,consultationTurn:patient.consultationTurn,state:'Pendiente',result:null,resultValues:[],releasedAt:null,weightKg:this.measure(this.weight,.1,500),heightCm:this.measure(this.height,20,250),requestedBy:this.activeDoctorID});
      this.modal=''; this.preparing = false; this.exam = ''; this.observation = ''; this.category = 'Todos'; this.filterDate = false;
      this.confirmation = 'Solicitud de ejemplo guardada para el paciente · Pendiente. No se envió al hospital.';
      return true;
    }
    configureDoctor(name,id,clinic) {
      const previous=this.activeDoctorID;this.doctorName=name;this.activeDoctorID=id;if(clinic)this.clinicName=clinic;
      for(const visit of this.visits)if(visit.doctorID===previous)visit.doctorID=id;
    }
    ownVisits(patientID) {return this.visits.filter(visit=>visit.patientID===patientID&&visit.doctorID===this.activeDoctorID).sort((a,b)=>b.date.localeCompare(a.date));}
    measure(text,min,max) {
      const clean=text.trim().replace(',','.');if(!/^\d{1,3}(\.\d{1,2})?$/.test(clean))return null;
      const value=Number(clean);return Number.isFinite(value)&&value>=min&&value<=max?value:null;
    }
    begin(role) {
      if(role!=='doctor'||!this.patient(role))return false;
      this.preparing=true;this.modal='request';this.exam='';this.observation='';this.weight='';this.height='';this.requestDate=new Date().toISOString();this.confirmation='';return true;
    }
    validPrescription() {
      const rx=this.rxDetails,positive=value=>/^\d{1,8}([.,]\d{1,4})?$/.test(value.trim())&&Number(value.replace(',','.'))>0&&Number.isFinite(Number(value.replace(',','.')));
      return positive(rx.dose)&&positive(rx.frequency)&&positive(rx.quantity)&&!!rx.unit.trim()&&!!rx.route.trim()&&/^\d{1,5}$/.test(rx.duration)&&Number(rx.duration)>0&&Number(rx.duration)<=36500;
    }
    saveEntry(role) {
      const patient=this.patient(role),text=this.entryText.trim();
      if(role!=='doctor'||!patient||!['Observación','Receta'].includes(this.entryKind)||!text||text.length>2000||(this.entryKind==='Receta'&&(!this.medication.trim()||!this.validPrescription()))||(this.linkedRequest&&!this.requests.some(request=>request.id===this.linkedRequest&&request.patient.id===patient.id)))return false;
      this.entries.unshift({id:root.crypto.randomUUID(),patientID:patient.id,requestID:this.linkedRequest,kind:this.entryKind,medication:this.entryKind==='Receta'?this.medication.trim():null,text,authorName:this.doctorName,authorID:this.activeDoctorID,createdAt:new Date().toISOString(),prescription:this.entryKind==='Receta'?{...this.rxDetails}:null});
      this.confirmation=this.entryKind==='Receta'?'Receta local guardada · Sin emisión clínica':'Observación local guardada';this.modal='';return true;
    }
    applyPublishedResult(id,values,narrative,publishedAt) {
      const request=this.requests.find(request=>request.id===id);
      if(!request||!Array.isArray(values)||(!values.length&&!narrative.trim())||!Number.isFinite(new Date(publishedAt).getTime())||(request.releasedAt&&new Date(publishedAt)<new Date(request.releasedAt)))return false;
      request.resultValues=values.map(value=>({...value}));request.result=narrative;request.releasedAt=publishedAt;request.state='Completado';this.ui.repaint?.();return true;
    }
    render(parent,{role,page}) {
      if(role==='patient'&&['chart','laboratory'].includes(page)&&!this.modal)this.modal=page==='chart'?'record':'results';
      const {el,button,repaint,go}=this.ui;
      const card=title=>{const node=el('article',null,'sched-card clinical-lab-card');node.append(el('h2',title,'section-title'));return node;};
      const detail=(parent,label,value)=>{const node=el('div',null,'consult-field');node.append(el('span',label),el('p',value));parent.append(node);};
      const field=(parent,label,type,value,onChange,options)=>{
        const group=el('label',label,'doctor-field'),input=el(options?'select':type==='textarea'?'textarea':'input');
        if(options)for(const[value,text]of options){const option=el('option',text);option.value=value;input.append(option);}else if(type!=='textarea')input.type=type;
        input.value=value;input.setAttribute('aria-label',label);input.disabled=this.ui.busy();input.addEventListener(options?'change':'input',()=>onChange(input.value));group.append(input);parent.append(group);return input;
      };
      const demographics=(node,patient)=>{for(const[label,value]of[['Nombre',patient.givenName],['Apellido',patient.familyName],['Correo electrónico',patient.email],['Edad',patient.age+' años'],['DUI',patient.dui],['Teléfono',patient.phone],['Expediente',patient.record]])detail(node,label,value);};
      const openEntry=(kind,id=null)=>{this.entryKind=kind;this.entryText='';this.medication='';this.rxDetails={dose:'',unit:'',frequency:'',route:'',duration:'',quantity:''};this.linkedRequest=id;this.modal='entry';repaint();};
      const entryButtons=(node,id=null)=>{if(role==='doctor')node.append(button('Añadir observación',()=>openEntry('Observación',id),'module-action'),button('Añadir receta',()=>openEntry('Receta',id),'module-action'));};
      const labList=(container,patient)=>{
        const labs=card('Laboratorios del expediente'),inRecord=this.modal==='record'||role==='patient';labs.append(el('p','Más recientes primero · Solicitudes y resultados del paciente','sched-hint'));
        if(!inRecord){
          field(labs,'Tipo de laboratorio','text',this.category,value=>{this.category=value;repaint();},['Todos','Orina','Heces','Sangre','Otros'].map(value=>[value,value]));
          const label=el('label',null,'doctor-toggle'),toggle=el('input');toggle.type='checkbox';toggle.checked=this.filterDate;toggle.setAttribute('aria-label','Filtrar laboratorios por fecha');toggle.addEventListener('change',()=>{this.filterDate=toggle.checked;repaint();});label.append(toggle,el('span','Filtrar laboratorios por fecha'));labs.append(label);
          if(this.filterDate)field(labs,'Fecha de laboratorio','date',this.date,value=>{this.date=value;repaint();});
        }
        const list=el('div',null,'clinical-lab-timeline'),rows=this.requests.filter(request=>request.patient.id===patient.id&&(inRecord||((this.category==='Todos'||request.exam.category===this.category)&&(!this.filterDate||dateKey(new Date(request.requestedAt))===this.date)))).sort((a,b)=>Date.parse(b.requestedAt)-Date.parse(a.requestedAt));
        if(!rows.length)list.append(el('p','Este paciente todavía no tiene exámenes registrados.','sched-hint'));
        for(const request of rows){
          const row=el('article',null,'clinical-lab-history-card');row.setAttribute('data-request-id',request.id);row.setAttribute('data-requested-at',request.requestedAt);
          const heading=el('div',null,'clinical-lab-history-heading'),date=el('div',null,'clinical-lab-date-badge');date.append(el('strong',new Date(request.requestedAt).getDate().toString()),el('span',new Intl.DateTimeFormat('es-GT',{month:'short'}).format(new Date(request.requestedAt))));const title=el('div');title.append(el('h3',request.exam.name),el('p',stamp(request.requestedAt),'sched-hint'));heading.append(date,title);
          row.append(heading,el('span',request.state,'clinical-lab-state '+(request.state==='Completado'?'is-completed':request.state==='En Proceso'?'is-processing':'is-pending')),el('p',request.state==='Completado'?((request.result?.trim()||request.resultValues?.length)?'Resultado disponible para revisión':'Informe pendiente de publicación'):request.state==='En Proceso'?'El laboratorio está procesando el examen':'Solicitud pendiente de procesamiento','sched-hint'));
          const open=button('Ver detalle',()=>{this.activeLabID=request.id;this.labReturnModal=this.modal;this.modal='lab-detail';repaint();},'clinical-lab-open');open.setAttribute('aria-label','Ver detalle: '+request.exam.name);row.append(open);list.append(row);
        }
        labs.append(list);container.append(labs);
      };
      parent.append(el('p','Prototipo local · Solicitudes y expediente de ejemplo · Sin escritura en Supabase','consult-demo'));
      if(!this.modal){
        const intro=el('article',null,'clinical-landing');intro.append(el('span',page==='patients'?'TU PRÁCTICA MÉDICA':page==='laboratory'?'ATENCIÓN CLÍNICA':'HISTORIA DEL PACIENTE','sched-eyebrow'),el('h2',page==='patients'?'Tus pacientes, su evolución':page==='laboratory'?'Laboratorio, paso a paso':'Un expediente, toda la información'),el('p',page==='patients'?'Busca por fecha, DUI o nombre. Abre una ficha para revisar su evolución clínica.':page==='laboratory'?'1. Busca al paciente. 2. Prepara su solicitud.':'Busca al paciente para abrir su ficha completa.'));parent.append(intro);
      }
      if(role==='doctor'){
        const search=card(page==='patients'?'Encuentra a tu paciente':page==='laboratory'?'Buscar paciente':'Buscar expediente'),list=el('div',null,page==='patients'?'patient-matches':'doctor-patients');
        const paint=()=>{
          list.replaceChildren();
          const patients=this.patients.filter(patient=>fold(this.fullName(patient)+' '+patient.dui).includes(fold(this.query))&&(page!=='patients'||!this.patientFilterDate||this.ownVisits(patient.id).some(visit=>dateKey(new Date(visit.date))===this.patientDate)));
          if(page==='patients')list.append(el('p',patients.length+' coincidencias · '+(this.patientFilterDate?'Fecha seleccionada':'Todos los registros'),'patient-match-count'));
          for(const patient of patients){
            const item=button(null,()=>{this.select(patient.id);if(['chart','patients'].includes(page))this.modal='record';repaint();},page==='patients'?'patient-match-card':'doctor-patient'+(this.selected===patient.id?' is-selected':''));item.setAttribute('aria-label','Seleccionar a '+this.fullName(patient));
            const text=el('div',null,'patient-match-info');text.append(el('strong',this.fullName(patient)),el('small','DUI: '+patient.dui+(page==='patients'?' · '+patient.age+' años':'')));
            if(page==='patients'){
              const visits=this.ownVisits(patient.id),pending=this.requests.filter(request=>request.patient.id===patient.id&&request.state!=='Completado').length;
              const initials=el('span',this.fullName(patient).split(' ').slice(0,2).map(word=>word[0]).join(''),'patient-match-avatar');item.append(initials);
              text.append(el('small','Teléfono: '+patient.phone),el('span',visits.filter(visit=>visit.status!=='Programada').length+' consultas · '+pending+' estudios pendientes','patient-match-progress'),el('small',visits[0]?'Última / próxima atención: '+stamp(visits[0].date):'Sin atenciones registradas'),el('span','Ver ficha e historial','patient-match-link'));
            }
            item.append(text);list.append(item);
          }
          if(!patients.length)list.append(el('p','No hay pacientes que coincidan. Prueba otra fecha, DUI o nombre.','sched-hint'));
        };
        field(search,'DUI o nombre del paciente','search',this.query,value=>{this.query=value;paint();});
        if(page==='patients'){
          const quick=el('div',null,'consult-days');for(const[offset,label]of[[null,'Todos'],[0,'Hoy'],[1,'Mañana']])quick.append(button(label,()=>{this.patientFilterDate=offset!==null;if(offset!==null){const day=new Date();day.setDate(day.getDate()+offset);this.patientDate=dateKey(day);}repaint();},'consult-day'+((offset===null&&!this.patientFilterDate)?' is-selected':'')));search.append(quick);
          field(search,'Fecha de atención','date',this.patientDate,value=>{this.patientDate=value;this.patientFilterDate=true;paint();});
        }
        paint();search.append(list);parent.append(search);
      }
      const patient=this.patient(role);
      if(!patient){parent.append(card('Selecciona un paciente para continuar'));return;}
      const summary=card(this.fullName(patient));detail(summary,'DUI',patient.dui);detail(summary,'Expediente',patient.record);
      if(page==='laboratory'&&role==='doctor')summary.append(button('Solicitar exámenes',()=>{this.begin(role);repaint();},'primary'));
      else{summary.append(button('Abrir expediente completo',()=>{this.modal='record';repaint();},'primary'));}
      if(page==='laboratory'&&role!=='doctor')summary.append(button('Ver solicitudes y resultados',()=>{this.modal='results';repaint();},'module-action'));
      if(page!=='patients')parent.append(summary);
      if(this.confirmation){const notice=el('p',this.confirmation,'consult-demo');notice.setAttribute('role','status');parent.append(notice);}
      if(role==='patient'&&page==='laboratory'&&!this.modal)this.modal='results';
      if(!this.modal)return;
      parent.replaceChildren(); parent.scrollTop=0;
      const dialog=el('section',null,'clinical-ticket');dialog.tabIndex=-1;dialog.setAttribute('role','region');dialog.setAttribute('aria-label',this.modal==='lab-detail'?'Detalle de examen':this.modal==='record'?(role==='patient'?'Mi expediente':'Expediente completo'):this.modal==='request'?'Solicitar exámenes':this.modal==='results'?(role==='patient'?'Mis laboratorios':'Solicitudes y resultados'):'Formulario de '+this.entryKind);
      const close=()=>{if(this.modal==='lab-detail'){this.modal=this.labReturnModal||'record';this.activeLabID=null;repaint();return;}this.modal='';this.preparing=false;if(role==='patient'&&['chart','laboratory'].includes(page))go('home');else repaint();};
      const top=el('div',null,'clinical-ticket-nav');top.append(button('Volver',close,'text-button'),el('span',this.modal==='request'?'PASO 2 DE 2':'FICHA CLÍNICA'));dialog.append(top);
      const selectedLab=this.requests.find(item=>item.id===this.activeLabID&&item.patient.id===patient.id);
      const icon=el('span',this.modal==='lab-detail'&&selectedLab?.state!=='Completado'?'◷':'\u2713','clinical-ticket-icon');icon.setAttribute('aria-hidden','true');
      const heading=this.modal==='lab-detail'?'Detalle de examen':this.modal==='record'?(role==='patient'?'Mi expediente':'Expediente completo'):this.modal==='request'?'Solicitar exámenes':this.modal==='results'?(role==='patient'?'Mis laboratorios':'Solicitudes y resultados'):this.entryKind;
      if(this.modal!=='lab-detail')dialog.append(icon);dialog.append(el('h2',heading,'clinical-ticket-title'));if(this.modal!=='lab-detail')dialog.append(el('p',this.fullName(patient),'clinical-ticket-patient'));
      const context=el('div',null,'clinical-ticket-context');context.append(el('strong',this.modal==='lab-detail'?(selectedLab?stamp(selectedLab.requestedAt):'No hay datos reales'):this.modal==='request'?stamp(this.requestDate):patient.record),el('span',this.modal==='lab-detail'?(selectedLab?.exam.name||'No hay datos reales'):this.modal==='request'?this.doctorName:'DUI: '+patient.dui));if(this.modal!=='lab-detail')dialog.append(context);
      dialog.append(el('small','Datos locales de ejemplo · Sin envío al hospital','clinical-ticket-note'));
      if(this.modal==='request'){
        const form=el('form',null,'clinical-lab-form');
        const automatic=el('div',null,'clinical-ticket-grid');detail(automatic,'Clínica',this.clinicName);detail(automatic,'Turno de consulta',patient.consultationTurn);form.append(automatic);
        const examGroup=el('fieldset',null,'clinical-ticket-group');examGroup.append(el('legend','01 · Examen y motivo'));form.append(examGroup);
        const clinicalGroup=el('fieldset',null,'clinical-ticket-group');clinicalGroup.append(el('legend','02 · Valoración clínica'));const measures=el('div',null,'clinical-ticket-grid');clinicalGroup.append(measures);form.append(clinicalGroup);
        let submit;const update=()=>{if(submit)submit.disabled=!this.canSubmit(role)||this.ui.busy();};
        field(examGroup,'Tipo de examen','text',this.exam,value=>{this.exam=value;update();},[['','Seleccionar examen'],...HospitalClinicalLabsDesign.exams.map(exam=>[exam.id,exam.name])]).required=true;
        field(examGroup,'Motivo del examen','textarea',this.observation,value=>{this.observation=value;update();}).required=true;
        for(const[label,key]of[['Peso (kg)','weight'],['Altura (cm)','height']]){const input=field(measures,label,'text',this[key],value=>{this[key]=value;update();});input.inputMode='decimal';input.required=true;}
        form.append(el('small','Obligatorios: peso 0,1–500 kg y altura 20–250 cm. Hasta dos decimales; coma o punto.','sched-hint'));
        submit=el('button','Solicitar','primary');submit.type='submit';update();form.append(submit);form.addEventListener('submit',event=>{event.preventDefault();if(this.submit(role))repaint();});form.append(button('Cancelar',close,'module-action'));dialog.append(form);
      }else if(this.modal==='entry'){
        const form=el('form',null,'clinical-lab-form');detail(form,'Paciente',this.fullName(patient));detail(form,'Doctor',this.doctorName);let save;
        const valid=()=>{if(save)save.disabled=!this.entryText.trim()||this.entryText.length>2000||(this.entryKind==='Receta'&&(!this.medication.trim()||!this.validPrescription()));};
        if(this.entryKind==='Receta'){form.append(el('p','Borrador local. No emite una receta clínica.','consult-demo'));field(form,'Medicamento','text',this.medication,value=>{this.medication=value;valid();}).required=true;
          for(const[label,key]of[['Dosis','dose'],['Unidad de dosis','unit'],['Cada cuántas horas','frequency'],['Vía','route'],['Durante (días)','duration'],['Cantidad a dispensar','quantity']]){const input=field(form,label,'text',this.rxDetails[key],value=>{this.rxDetails[key]=value;valid();});input.required=true;if(!['unit','route'].includes(key))input.inputMode=key==='duration'?'numeric':'decimal';}
        }
        field(form,this.entryKind==='Receta'?'Observaciones':'Observación','textarea',this.entryText,value=>{this.entryText=value;valid();}).required=true;
        save=el('button','Guardar','primary');save.type='submit';valid();form.append(save);form.addEventListener('submit',event=>{event.preventDefault();if(this.saveEntry(role))repaint();});dialog.append(form);
      }else if(this.modal==='lab-detail'){
        const request=selectedLab;
        if(!request)dialog.append(el('p','Este examen no está disponible para el paciente seleccionado.','sched-hint'));
        else{
          const personal=card('Paciente');personal.className+=' lab-detail-patient';
          const identity=el('div',null,'lab-detail-identity'),avatar=el('span',[request.patient.givenName,request.patient.familyName].map(value=>value?.trim()?.[0]||'').join('')||'?','record-person-avatar');avatar.setAttribute('aria-hidden','true');identity.append(avatar);detail(identity,'Nombre completo',this.fullName(request.patient));personal.append(identity);
          const contact=el('div',null,'lab-detail-contact');detail(contact,'Edad',request.patient.age>=0?request.patient.age+' años':'No hay datos reales');detail(contact,'Teléfono',request.patient.phone);personal.append(contact);dialog.append(personal);
          const info=card('Información del examen');info.className+=' lab-detail-exam';info.append(el('h3',request.exam.name,'clinical-lab-detail-name'),el('span',request.state,'clinical-lab-state '+(request.state==='Completado'?'is-completed':request.state==='En Proceso'?'is-processing':'is-pending')));
          const date=el('div',null,'clinical-ticket-context');date.append(el('span','Fecha de solicitud'),el('strong',stamp(request.requestedAt)));info.append(date);
          for(const[label,value]of[['Tipo de examen',request.exam.category],['Doctor solicitante',request.doctorName],['Turno',request.consultationTurn],['Clínica',request.clinicName],['Motivo del examen',request.observation]])detail(info,label,value);dialog.append(info);
          const result=card('Resultado del examen');result.className+=' lab-detail-result';
          if(request.state==='Completado'){
            if(request.releasedAt)detail(result,'Fecha de publicación',stamp(request.releasedAt));
            for(const value of request.resultValues||[]){const item=el('div',null,'clinical-result-value');item.append(el('span',value.name),el('small','Valor obtenido','clinical-result-label'),el('strong',(value.value||'No hay datos reales')+' '+(value.unit||'')),el('small','Referencia: '+(value.reference||'No hay datos reales')));result.append(item);}
            detail(result,'Observación del laboratorio',request.result||'No hay un informe publicado todavía');
          }else{result.append(el('h3',request.state),el('p',request.state==='En Proceso'?'El examen se está procesando. Los resultados aparecerán aquí cuando se publiquen.':'La solicitud está registrada y espera procesamiento. Todavía no hay resultados publicados.','sched-hint'));}
          dialog.append(result);entryButtons(dialog,request.id);
        }
        dialog.append(button(this.labReturnModal==='record'?'Volver al expediente':'Volver a laboratorios',close,'consult-ticket-primary'));
      }else if(this.modal==='results'){labList(dialog,patient);
      }else{
        const personal=card('Datos personales');personal.append(root.HospitalClinicalIdentity(el,patient));dialog.append(personal);
        const history=card(role==='patient'?'Historial clínico':'Historial clínico de mis consultas');history.append(el('p',role==='patient'?'Consultas registradas en tu expediente.':'Solo tus consultas con este paciente. Las próximas citas no son antecedentes clínicos.','sched-hint'));
        const visits=this.ownVisits(patient.id).filter(visit=>visit.status!=='Programada');
        if(!visits.length)history.append(el('p','Sin consultas previas registradas.','sched-hint'));
        for(const visit of visits){const row=el('article',null,'patient-history-row');row.append(el('span',stamp(visit.date),'patient-history-date'),el('strong',visit.reason),el('p',visit.plan),el('span',visit.status,'patient-visit-state'));history.append(row);}dialog.append(history);
        const vitals=card('Historial y signos vitales'),last=this.requests.filter(request=>request.patient.id===patient.id&&request.weightKg).sort((a,b)=>b.requestedAt.localeCompare(a.requestedAt))[0];detail(vitals,'Peso',last?last.weightKg+' kg':'No hay datos reales');detail(vitals,'Altura',last?last.heightCm+' cm':'No hay datos reales');detail(vitals,'Otros signos vitales y antecedentes','Sin registros en este prototipo; no se inventan antecedentes.');if(last)detail(vitals,'Registrado por',last.doctorName+' · '+stamp(last.requestedAt));dialog.append(vitals);
        const entries=card('Notas y recetas'),rows=this.entries.filter(entry=>entry.patientID===patient.id);if(!rows.length)entries.append(el('p','Sin notas ni recetas registradas.','sched-hint'));
        for(const entry of rows){const row=card(entry.kind==='Receta'?'Receta local · No emitida':'Observación');if(entry.medication)detail(row,'Medicamento',entry.medication);if(entry.prescription){const rx=entry.prescription;for(const[label,value]of[['Dosis',rx.dose+' '+rx.unit],['Cada',rx.frequency+' horas'],['Vía',rx.route],['Durante',rx.duration+' días'],['Cantidad',rx.quantity]])detail(row,label,value);}detail(row,entry.kind==='Receta'?'Observaciones':'Nota',entry.text);detail(row,'Registrado por',entry.authorName+' · '+stamp(entry.createdAt));entries.append(row);}entryButtons(entries);dialog.append(entries);labList(dialog,patient);
      }
      parent.append(dialog);
    }
  }
  root.HospitalClinicalIdentity=(el,patient)=>{
    const clean=value=>String(value??'').trim()||'No hay datos reales',content=el('div',null,'record-person-content'),identity=el('div',null,'record-person-identity'),avatar=el('span',[patient.givenName,patient.familyName].map(value=>value?.trim()?.[0]||'').join('')||'?','record-person-avatar'),text=el('div');avatar.setAttribute('aria-hidden','true');text.append(el('h3',clean(patient.fullName||[patient.givenName,patient.familyName].filter(Boolean).join(' '))),el('p','Paciente · Información registrada'));identity.append(avatar,text);content.append(identity);
    const grid=el('div',null,'record-person-grid');for(const[label,value]of[['Nombre',patient.givenName],['Apellido',patient.familyName],['Edad',typeof patient.age==='number'?(patient.age>=0?patient.age+' años':null):patient.age],['DUI',patient.dui]]){const block=el('div',null,'record-person-field');block.append(el('span',label),el('strong',clean(value)));grid.append(block);}content.append(grid);
    for(const[label,value,symbol]of[['Correo electrónico',patient.email,'@'],['Teléfono',patient.phone,'☎'],['Expediente',patient.record,'▤']]){const line=el('div',null,'record-person-contact'),icon=el('span',symbol,'record-person-contact-icon'),text=el('div');icon.setAttribute('aria-hidden','true');text.append(el('span',label),el('strong',clean(value)));line.append(icon,text);content.append(line);}return content;
  };
  root.HospitalClinicalLabsDesign=HospitalClinicalLabsDesign;
})(typeof window!=='undefined'?window:globalThis);

(function(root){
  'use strict';
  class HospitalPatientClinical {
    constructor(ui){this.ui=ui;this.reset();}
    reset(){this.selected=null;this.page=null;}
    render(parent,{page,profile,scope}){
      const{el,button,repaint,go,model,laboratory,run}=this.ui,main=model(),source=page==='chart'?laboratory():main;
      if(this.page!==page||this.scope!==scope){this.selected=null;this.page=page;this.scope=scope;}
      if(this.ui.busy()){parent.append(el('p','Cargando tu información…','loading'));return;}
      if(!main.data){parent.append(el('p','No pudimos cargar tu información. Intenta de nuevo.','scope-note'),button('Reintentar',this.ui.retry,'module-action'));return;}
      const fields=page==='chart'?(main.data.sections||[]).flatMap(section=>section.fields):[],clean=value=>typeof value==='string'&&value.trim()?value.trim():'No hay datos reales';
      const value=label=>fields.find(item=>item.label.toLowerCase()===label.toLowerCase())?.value;
      const name=clean(value('Nombre')||(profile?.person?[profile.person.given_names,profile.person.family_names].join(' '):null)),age=clean(value('Edad')),phone=clean(value('Teléfono')||profile?.contacts?.find(item=>item.kind==='phone')?.value);
      const stamp=text=>Number.isFinite(Date.parse(text))?new Intl.DateTimeFormat('es-GT',{dateStyle:'long',timeStyle:'short'}).format(new Date(text)):'No hay datos reales';
      const completed=item=>['released','completed'].includes(item.status),state=item=>({pending:'Pendiente',in_progress:'En Proceso',processing:'En Proceso',released:'Completado',completed:'Completado',cancelled:'Cancelado'})[item.status]||'Estado no disponible';
      const badge=item=>el('span',state(item),'clinical-lab-state '+(completed(item)?'is-completed':item.status==='pending'?'is-pending':'is-processing'));
      const records=[...source.items].sort((a,b)=>(Date.parse(b.event_at)||0)-(Date.parse(a.event_at)||0)),selected=records.find(item=>item.id===this.selected);
      const ticket=el('section',null,'clinical-ticket patient-own-chart');ticket.setAttribute('role','region');ticket.setAttribute('aria-label',selected?'Detalle de examen':page==='chart'?'Mi expediente completo':'Mis laboratorios');
      const close=()=>{if(this.selected){this.selected=null;repaint();}else go('home');},nav=el('div',null,'clinical-ticket-nav');nav.append(button('Volver',close,'text-button'),el('span','ACCESO PERSONAL'));ticket.append(nav);
      const card=title=>{const node=el('section',null,'clinical-lab-card');node.append(el('h3',title));return node;};
      const field=(parent,label,text)=>{const row=el('div',null,'consult-field');row.append(el('span',label),el('p',clean(text)));parent.append(row);};
      const person=full=>{const node=card(full?'Datos personales':'Paciente');if(full){node.append(root.HospitalClinicalIdentity(el,{givenName:profile?.person?.given_names||value('Nombres'),familyName:profile?.person?.family_names||value('Apellido'),fullName:name,age,dui:value('DUI'),email:profile?.auth_email,phone,record:value('Expediente')}));return node;}node.className+=full?'':' lab-detail-patient';const identity=el('div',null,'lab-detail-identity'),avatar=el('span',name==='No hay datos reales'?'?':name.split(' ').slice(0,2).map(item=>item[0]).join(''),'record-person-avatar');avatar.setAttribute('aria-hidden','true');identity.append(avatar);field(identity,'Nombre completo',name);node.append(identity);const contact=el('div',null,'lab-detail-contact');field(contact,'Edad',age);field(contact,'Teléfono',phone);node.append(contact);if(full){field(node,'Correo',profile?.auth_email);field(node,'DUI',value('DUI'));field(node,'Expediente',value('Expediente'));}return node;};
      const document=(node,item,owner)=>{if(!item.document_id)return;const signed=owner.documents.get(item.document_id);if(signed&&signed.expires>Date.now()){const a=el('a','Abrir documento autorizado','module-action');a.href=signed.url;a.target='_blank';a.rel='noopener noreferrer';node.append(a);}else node.append(button('Autorizar documento',()=>run(async()=>{const url=await owner.api.documentURL(item.document_id);owner.documents.set(item.document_id,{url,expires:Date.now()+50000});}),'module-action'));};
      if(selected){
        ticket.append(el('h2','Detalle de examen','clinical-ticket-title'),person(false));
        const info=card('Información del examen');info.className+=' lab-detail-exam';info.append(el('h3',selected.title,'clinical-lab-detail-name'),badge(selected));const date=el('div',null,'clinical-ticket-context');date.append(el('span','Fecha de solicitud'),el('strong',stamp(selected.event_at)));info.append(date);field(info,'Motivo del examen',selected.details?.find(item=>item.label==='Indicaciones')?.value);ticket.append(info);
        const result=card('Resultado del examen');result.className+=' lab-detail-result';if(completed(selected)){const values=(selected.details||[]).filter(item=>item.label!=='Indicaciones');for(const item of values){const row=el('div',null,'clinical-result-value');row.append(el('span',item.label),el('small','Valor publicado','clinical-result-label'),el('strong',clean(item.value)));result.append(row);}if(!values.length)result.append(el('p','No hay un informe publicado todavía.','sched-hint'));document(result,selected,source);}else result.append(el('h3',state(selected)),el('p','Los resultados aparecerán aquí cuando el laboratorio los publique.','sched-hint'));ticket.append(result,button(page==='chart'?'Volver a mi expediente':'Volver a mis laboratorios',close,'consult-ticket-primary'));
      }else{
        const icon=el('span',page==='chart'?'\u2713':'⚗','clinical-ticket-icon');icon.setAttribute('aria-hidden','true');ticket.append(icon,el('h2',page==='chart'?'Mi expediente':'Mis laboratorios','clinical-ticket-title'),el('p','Tu información médica · Acceso personal de solo lectura','clinical-ticket-note'));
        if(page==='chart'){ticket.append(person(true));for(const section of main.data.sections||[]){const group=card(section.title);for(const item of section.fields)field(group,item.label,item.value);if(!section.fields.length)group.append(el('p','Sin registros publicados.','sched-hint'));ticket.append(group);}for(const item of main.items){const group=card(item.title);for(const detail of item.details||[])field(group,detail.label,detail.value);document(group,item,main);ticket.append(group);}if(main.data.has_more)ticket.append(button('Cargar más documentos',()=>run(()=>main.load('chart',true)),'module-action'));}
        const labs=card('Laboratorios del expediente');labs.append(el('p','Más recientes primero · Solicitudes y resultados del paciente','sched-hint'));
        if(!source.data)labs.append(el('p','No pudimos cargar tus laboratorios.','scope-note'),button('Reintentar laboratorios',()=>run(()=>source.load('laboratory')),'module-action'));
        else if(!records.length)labs.append(el('p','Todavía no tienes exámenes registrados.','sched-hint'));
        for(const item of records){const row=el('article',null,'clinical-lab-history-card');row.setAttribute('data-requested-at',item.event_at);const heading=el('div',null,'clinical-lab-history-heading'),date=el('div',null,'clinical-lab-date-badge'),title=el('div');if(Number.isFinite(Date.parse(item.event_at))){date.append(el('strong',new Date(item.event_at).getDate().toString()),el('span',new Intl.DateTimeFormat('es-GT',{month:'short'}).format(new Date(item.event_at))));heading.append(date);}title.append(el('h3',item.title),el('p',stamp(item.event_at),'sched-hint'));heading.append(title);row.append(heading,badge(item),el('p',completed(item)?'Resultado disponible para revisión':item.status==='pending'?'Solicitud pendiente de procesamiento':item.status==='cancelled'?'Solicitud cancelada':'El laboratorio está procesando el examen','sched-hint'));const open=button('Ver detalle',()=>{this.selected=item.id;repaint();},'clinical-lab-open');open.setAttribute('aria-label','Ver detalle: '+item.title);row.append(open);labs.append(row);}labs.append(button('Actualizar laboratorios',()=>run(()=>source.load('laboratory')),'text-button'));if(source.data?.has_more)labs.append(button('Cargar más laboratorios',()=>run(()=>source.load('laboratory',true)),'module-action'));ticket.append(labs);
      }
      parent.append(ticket);
    }
  }
  root.HospitalPatientClinical=HospitalPatientClinical;
})(typeof window!=='undefined'?window:globalThis);
