(function(){
const P=[
 {id:'salvia',name:'Sálvia & Palha',designer:'Imagem de referência',ref:'Parede verde-sálvia, rattan, poltrona rosé e madeira clara.',mode:'light',ink:[34,45,33],window:'#E7EBE2',content:'#FBFBF7',alt:'#F3F4EE',side:'#DFE4D8',desk:'#9DB497',accent:'#8E4A63',atext:'#8E4A63',dest:'#C8102E',succ:'#2F6B3A',warn:'#7A5800',info:'#2D6680',cats:['#8E4A63','#4E7A52','#A9602F']},
 {id:'bergamin',name:'Azulejo',designer:'Sig Bergamin',ref:'Maximalismo brasileiro: porcelana azul e branca com toques de coral.',mode:'light',ink:[18,28,66],window:'#ECEEF3',content:'#FFFFFF',alt:'#F5F6FA',side:'#E3E6EF',desk:'#BFCBEA',accent:'#2B4FB3',atext:'#2A4BAA',dest:'#C8102E',succ:'#2E7A3E',warn:'#8A5A00',info:'#1F6F92',cats:['#2B4FB3','#C24A33','#2E7A3E']},
 {id:'draper',name:'Hampshire',designer:'Dorothy Draper',ref:'Preto e branco de alto contraste, verde laqueado e rosa.',mode:'light',ink:[20,24,22],window:'#EEEDEA',content:'#FFFFFF',alt:'#F6F5F2',side:'#E6E4DF',desk:'#E7B9C2',accent:'#14705F',atext:'#11685A',dest:'#C8102E',succ:'#5C7A12',warn:'#8A5A00',info:'#2468A0',cats:['#14705F','#C2456E','#3A3A3A']},
 {id:'mahdavi',name:'Veludo Rosé',designer:'India Mahdavi',ref:'Rosa empoeirado da Gallery do Sketch, ameixa, mostarda e verde.',mode:'light',ink:[52,24,40],window:'#F3E9E6',content:'#FFFCFB',alt:'#FAF2EF',side:'#EEDFDB',desk:'#E9B8B0',accent:'#8B356B',atext:'#82305F',dest:'#C8102E',succ:'#2F6B3A',warn:'#7A5800',info:'#2D6680',cats:['#8B356B','#9A7012','#2F6B4F']},
 {id:'wearstler',name:'Terracota',designer:'Kelly Wearstler',ref:'Espresso, terracota, latão escovado e pedra californiana.',mode:'dark',ink:[255,246,236],window:'#2A2420',content:'#1C1815',alt:'#221D19',side:'#302925',desk:'#3B2A20',accent:'#B4532F',atext:'#EE9B73',dest:'#FF4D6A',succ:'#8FD685',warn:'#F5C451',info:'#9BCFE0',cats:['#EE9B73','#C9B07A','#A9C49A']},
 {id:'garcia',name:'Costes',designer:'Jacques Garcia',ref:'Vermelho sangue-de-boi, veludo e dourado do Hôtel Costes.',mode:'dark',ink:[255,242,236],window:'#2A1C1F',content:'#1B1113',alt:'#221619',side:'#321F23',desk:'#3E1A20',accent:'#D2AE5C',onA:'#24170E',atext:'#E3C27A',dest:'#FF5E7A',succ:'#7FD6A8',warn:'#FF8A3D',info:'#9BCFE0',cats:['#E3C27A','#E08A8A','#9BB89A']},
 {id:'hicks',name:'Geométrico',designer:'David Hicks',ref:'Berinjela, violeta, laranja e rosa-choque em padrões geométricos.',mode:'dark',ink:[246,240,255],window:'#251F2C',content:'#17131C',alt:'#1D1823',side:'#2C2534',desk:'#2E1F3A',accent:'#7B54C8',atext:'#C2A5FF',dest:'#FF6961',succ:'#8FD685',warn:'#F5C451',info:'#9BCFE0',cats:['#C2A5FF','#FF9466','#FF8FC7']},
 {id:'dirand',name:'Mármore',designer:'Joseph Dirand',ref:'Monocromia de mármore escuro, pedra clara e azul ardósia.',mode:'dark',ink:[240,244,248],window:'#232528',content:'#151618',alt:'#1B1C1F',side:'#2A2C30',desk:'#2C3036',accent:'#476C96',atext:'#9DBEE3',dest:'#FF6961',succ:'#8FD685',warn:'#F5C451',info:'#9BDCD0',cats:['#9DBEE3','#C9BBA4','#9ACBB5']},
 {id:'tudisco',name:'Jardim Digital',designer:'Antoni Tudisco',ref:'Céu lavanda, violeta elétrico, flor de cerejeira e vermelho de esmalte.',mode:'light',extra:true,ink:[30,20,70],window:'#ECE9F6',content:'#FFFFFF',alt:'#F6F4FC',side:'#E4DFF3',desk:'#C9C2EE',accent:'#5A3CC8',atext:'#5234B8',dest:'#C8102E',succ:'#2E7A3E',warn:'#8A5A00',info:'#1F6F92',cats:['#5A3CC8','#C2457F','#1F7A86']},
];
const hx=h=>[1,3,5].map(i=>parseInt(h.slice(i,i+2),16));
const toHex=a=>'#'+a.map(v=>Math.round(Math.max(0,Math.min(255,v))).toString(16).padStart(2,'0')).join('').toUpperCase();
const mixHex=(a,b,t)=>toHex(hx(a).map((v,i)=>v*(1-t)+hx(b)[i]*t));
const rgba=(rgb,a)=>`rgba(${rgb.join(',')},${a})`;
const lin=c=>{c/=255;return c<=.04045?c/12.92:((c+.055)/1.055)**2.4};
const lum=rgb=>.2126*lin(rgb[0])+.7152*lin(rgb[1])+.0722*lin(rgb[2]);
const cr=(a,b)=>{const x=lum(a),y=lum(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05)};
const over=(fg,a,bg)=>fg.map((v,i)=>v*a+bg[i]*(1-a));
const oklab=rgb=>{const [r,g,b]=rgb.map(lin);const l=Math.cbrt(.4122214708*r+.5363325363*g+.0514459929*b),m=Math.cbrt(.2119034982*r+.6806995451*g+.1073969566*b),s=Math.cbrt(.0883024619*r+.2817188376*g+.6299787005*b);return [.2104542553*l+.793617785*m-.0040720468*s,1.9779984951*l-2.428592205*m+.4505937099*s,.0259040371*l+.7827717662*m-.808675766*s]};
const dE=(a,b)=>{const x=oklab(a),y=oklab(b);return Math.hypot(x[0]-y[0],x[1]-y[1],x[2]-y[2])};

function vars(p){
  const L=p.mode==='light', k=p.ink, A=hx(p.accent), T=hx(p.atext);
  const al=L?{p:.90,s:.68,t:.42,q:.20,sep:.11,sepS:.20,f1:.10,f2:.07,f3:.045,f4:.025,grp:.035,ch:.06,cp:.12,cb:.14,sel:.10}
           :{p:.90,s:.60,t:.34,q:.17,sep:.10,sepS:.18,f1:.12,f2:.08,f3:.05,f4:.03,grp:.04,ch:.08,cp:.15,cb:.12,sel:.12};
  return {
    '--label-primary':rgba(k,al.p),'--label-secondary':rgba(k,al.s),'--label-tertiary':rgba(k,al.t),'--label-quaternary':rgba(k,al.q),
    '--separator':rgba(k,al.sep),'--separator-strong':rgba(k,al.sepS),
    '--fill-primary':rgba(k,al.f1),'--fill-secondary':rgba(k,al.f2),'--fill-tertiary':rgba(k,al.f3),'--fill-quaternary':rgba(k,al.f4),
    '--bg-desktop':p.desk,'--bg-window':p.window,'--bg-sidebar':rgba(hx(p.side),.78),'--bg-sidebar-solid':p.side,
    '--bg-content':p.content,'--bg-content-alt':p.alt,'--bg-group':rgba(k,al.grp),
    '--bg-control':L?p.content:rgba(k,.10),'--bg-control-hover':rgba(k,al.ch),'--bg-control-pressed':rgba(k,al.cp),
    '--bg-field':L?p.content:rgba(k,.06),'--control-border':rgba(k,al.cb),'--scrim':L?rgba(k,.18):'rgba(0,0,0,.35)',
    '--accent':p.accent,'--accent-hover':L?mixHex(p.accent,'#000000',.07):mixHex(p.accent,'#FFFFFF',.08),
    '--accent-pressed':mixHex(p.accent,'#000000',.16),'--on-accent':p.onA||'#FFFFFF','--accent-text':p.atext,
    '--accent-tint':rgba(L?A:T,L?.16:.22),'--focus-ring':rgba(L?A:T,L?.55:.60),
    '--selection':p.accent,'--selection-text':p.onA||'#FFFFFF','--selection-inactive':rgba(k,al.sel),
    '--selection-inactive-text':rgba(k,al.p),'--selection-content':rgba(L?A:T,L?.14:.20),
    '--destructive':p.dest,'--destructive-fill':L?p.dest:'#E5303F','--success':p.succ,'--success-tint':rgba(hx(p.succ),L?.16:.18),
    '--warning':p.warn,'--warning-tint':rgba(hx(p.warn),L?.16:.16),'--danger-tint':rgba(hx(p.dest),L?.10:.14),
    '--info':p.info,'--recording':p.dest,'--cat-1':p.cats[0],'--cat-2':p.cats[1],'--cat-3':p.cats[2],'--chip-button':p.atext,
    '--status-2xx':p.succ,'--status-3xx':p.warn,'--status-4xx':p.dest,'--http-delete':p.dest
  };
}
function hc(p){
  const L=p.mode==='light';
  return {'--accent':mixHex(p.accent,'#000000',.16),'--selection':mixHex(p.accent,'#000000',.16),
    '--accent-text':L?mixHex(p.atext,toHex(p.ink),.3):mixHex(p.atext,'#FFFFFF',.35),
    '--label-primary':L?toHex(p.ink):'#FFFFFF','--label-secondary':rgba(p.ink,.82),'--label-tertiary':rgba(p.ink,.62),
    '--separator':rgba(p.ink,.34),'--separator-strong':rgba(p.ink,.55),'--control-border':rgba(p.ink,.60),'--bg-sidebar':p.side};
}
function checks(p){
  const c=hx(p.content), w=hx(p.window), L=p.mode==='light', A=hx(p.accent);
  const r=[
    {k:'Texto principal',v:cr(over(p.ink,.9,c),c),min:7},
    {k:'Texto secundário',v:cr(over(p.ink,L?.68:.6,w),w),min:4.5},
    {k:'Texto sobre destaque',v:cr(hx(p.onA||'#FFFFFF'),A),min:4.5},
    {k:'Link / texto de destaque',v:cr(hx(p.atext),w),min:4.5},
    {k:'Erro',v:cr(hx(p.dest),c),min:4.5},
    {k:'Sucesso',v:cr(hx(p.succ),c),min:4.5},
    {k:'Aviso',v:cr(hx(p.warn),c),min:4.5},
  ].map(x=>({...x,label:x.v.toFixed(1)+':1',ok:x.v>=x.min}));
  const d=Math.min(dE(A,hx(p.dest)),dE(A,hx(p.succ)),dE(A,hx(p.warn)),dE(hx(p.atext),hx(p.dest)),dE(hx(p.atext),hx(p.warn)));
  r.push({k:'Destaque ≠ erro/aviso/sucesso',v:d,min:.1,label:'ΔE '+d.toFixed(2),ok:d>=.1});
  return r;
}
const block=(sel,o)=>sel+'{\n'+Object.entries(o).map(([a,b])=>'  '+a+': '+b+';').join('\n')+'\n}';
function css(p){
  const t=p.mode==='dark'?'[data-theme="dark"]':'';
  return `/* ${p.name} · ${p.designer} · ${p.mode==='light'?'claro':'escuro'} — use <html data-palette="${p.id}"${p.mode==='dark'?' data-theme="dark"':''}> */\n`+
    block(`[data-palette="${p.id}"]`,vars(p))+'\n'+
    block(`[data-palette="${p.id}"][data-contrast="high"]`+t,hc(p));
}
window.MB_PALETTES={list:P,vars,checks,css,swatches:p=>[
  {n:'Janela',c:p.window},{n:'Conteúdo',c:p.content},{n:'Sidebar',c:p.side},{n:'Texto',c:toHex(p.ink)},
  {n:'Destaque',c:p.accent},{n:'Link',c:p.atext},{n:'Cat. 2',c:p.cats[1]},{n:'Cat. 3',c:p.cats[2]},
  {n:'Sucesso',c:p.succ},{n:'Aviso',c:p.warn},{n:'Erro',c:p.dest}]};
})();
