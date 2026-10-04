'use strict';
const fs=require('fs');
const puppeteer=require('puppeteer-core');
const CHROME=process.env.CHROME_BIN||'/tmp/chr/chromium';
process.env.LD_LIBRARY_PATH='/tmp/chr/lib:'+(process.env.LD_LIBRARY_PATH||'');
const URL=process.argv[2]||'http://localhost:8111/';
const OUT=process.argv[3]||'screenshots/kaykit-cast.png';
(async()=>{
  const b=await puppeteer.launch({headless:true,executablePath:CHROME,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  const p=await b.newPage();
  await p.setViewport({width:1280,height:720,deviceScaleFactor:1});
  await p.goto(URL,{waitUntil:'networkidle2'});
  const OPT={chars:process.env.CHARS||'trooper,grunt,runner,brute,splitter,bomber,shielder,boss',clip:process.env.CLIP||'',spacing:+(process.env.SPACING||1.35),perRow:+(process.env.PERROW||4),half:+(process.env.HALF||2.6),cy:+(process.env.CY||-1.0),yrot:+(process.env.YROT||0.55),spin:+(process.env.SPIN||0)};
  const png=await p.evaluate(async(OPT)=>{
    document.body.innerHTML='';
    const W=1280,H=720;
    const cv=document.createElement('canvas');cv.width=W;cv.height=H;document.body.appendChild(cv);
    const r=new THREE.WebGLRenderer({canvas:cv,antialias:true});r.setClearColor(0x1a2030);
    const sc=new THREE.Scene();
    sc.add(new THREE.HemisphereLight(0xffffff,0x606080,1.15));
    const d=new THREE.DirectionalLight(0xffffff,0.8);d.position.set(3,5,4);sc.add(d);
    const names=OPT.chars.split(',');
    const loader=new THREE.GLTFLoader();
    const CLIP=OPT.clip;const clipFor=new Proxy({},{get:(t,k)=>CLIP||({trooper:'shoot',grunt:'run',runner:'run',brute:'shoot',splitter:'shoot',bomber:'idle',shielder:'idle',boss:'run'})[k]});
    const SPACING=OPT.spacing, ROWY=[0,-2.6];
    for(let i=0;i<names.length;i++){
      const g=await new Promise((res,rej)=>loader.load(names[i].indexOf('/')>=0?names[i]:'assets/models/rigged/'+names[i]+'.glb',res,undefined,rej));
      // Material disalin ulang persis seperti di render3d.js: tekstur atlas
      // KayKit dipertahankan dan dibaca Linear (outputEncoding renderer juga
      // Linear), kalau tidak modelnya menggelap. Dulu baris ini memaksa
      // vertexColors dan hasilnya siluet hitam karena GLB sudah tak punya
      // COLOR_0 lagi.
      g.scene.traverse(c=>{if(c.isMesh||c.isSkinnedMesh){
        const m=c.material||{};
        if(m.map){m.map.encoding=THREE.LinearEncoding;m.map.flipY=false;m.map.needsUpdate=true;}
        c.material=new THREE.MeshLambertMaterial({map:m.map||null,color:0xffffff,
          vertexColors:!!(c.geometry&&c.geometry.attributes.color),skinning:!!c.isSkinnedMesh});
        c.frustumCulled=false;}});
      const perRow=OPT.perRow;const col=i%perRow,row=Math.floor(i/perRow);
      g.scene.position.set((col-(perRow-1)/2)*SPACING, ROWY[row], 0);
      g.scene.rotation.y=OPT.yrot+i*(OPT.spin||0);
      sc.add(g.scene);
      const m=new THREE.AnimationMixer(g.scene);
      const clip=g.animations.length?(g.animations.find(a=>a.name===clipFor[names[i]])||g.animations[0]):null;
      if(clip){m.clipAction(clip).play();m.setTime(clip.duration*0.4);m.update(0);}
    }
    const aspect=W/H, half=OPT.half;
    const cam=new THREE.OrthographicCamera(-half*aspect,half*aspect,half,-half,0.1,100);
    const cy=OPT.cy;cam.position.set(0,cy,10);cam.lookAt(0,cy,0);
    r.render(sc,cam);
    return cv.toDataURL('image/png');
  }, OPT);
  fs.writeFileSync(OUT,Buffer.from(png.split(',')[1],'base64'));
  await b.close();
})();
