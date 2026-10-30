#!/usr/bin/env node
// Recreate the portable overview from SVG artwork and captured app screens.
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const sharp=require('sharp');
const base=__dirname;
const W=1800,H=1210,cardW=308,screenW=296,screenH=641,top=337;
const green='#197E64',ink='#243E34',muted='#5E7669';
const xs=[80,413,746,1079,1412];
const labels=['App 图标','启动页','收集文案','走向多语言','校对并交付'];
const tags=['00 / IDENTITY','01 / LAUNCH','02 / COLLECT','03 / TRANSLATE','04 / DELIVER'];
const notes=[['双语卡片，轻轻叠放。','把每一句话，装进语言包。'],['暖白留白，品牌居中。','在本地数据加载时自然衔接。'],['文字输入，或导入文档。','从清晰的语言条目开始。'],['选择目标语言与翻译平台。','新增文案，接着完成。'],['检查译文与占位符。','有序导出 JSON / ZIP。']];
const text=(x,y,value,size=14,color=ink,weight=400,extra='')=>`<text x="${x}" y="${y}" font-family="PingFang SC,Arial,sans-serif" font-size="${size}" font-weight="${weight}" fill="${color}" ${extra}>${value}</text>`;
let content=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><rect width="1800" height="1210" fill="#F5F8F4"/>`;
content+=text(80,64,'LANGPACK / BRAND &amp; FIRST EXPERIENCE',12,green,600,'letter-spacing="2"');
content+=text(1720,64,'本地设计稿 · 1.0',12,muted,400,'text-anchor="end"');
content+=text(80,145,'译包 LangPack',47,ink,600,'letter-spacing="-1.5"');
content+=text(80,209,'从一句话，到每一种语言',47,green,600,'letter-spacing="-1.5"');
content+=text(1720,166,'让文案有处安放，让表达跨越语言。',16,muted,400,'text-anchor="end"');
content+=text(1720,198,'导入文案  →  多语翻译  →  校对交付',13,green,500,'text-anchor="end"');
content+='<path d="M80 263H1720" stroke="#DFE8DF"/>';
for(let i=0;i<5;i++){
 const x=xs[i];
 content+=text(x,310,labels[i],16,ink,600);
 content+=text(x+cardW,310,tags[i],10,muted,400,'text-anchor="end" letter-spacing=".4"');
 content+=`<rect x="${x}" y="${top+8}" width="${cardW}" height="653" rx="32" fill="#1B5D3C" fill-opacity=".035"/><rect x="${x}" y="${top}" width="${cardW}" height="653" rx="32" fill="#fff" stroke="#D5DFD5"/>`;
 content+=text(x+2,1030,notes[i][0],14,muted);
 content+=text(x+2,1055,notes[i][1],14,muted);
}
content+='<path d="M80 1100H1720" stroke="#DFE8DF"/>';
content+=text(80,1141,'WORDS WITHOUT BORDERS',11,green,600,'letter-spacing="2"');
content+=text(80,1172,'双语叠卡  /  暖白留白  /  轻量工作台',13,muted);
for(const [i,color] of ['#197E64','#CDE9D9','#F5F8F4'].entries()){
 const x=1100+i*218;
 content+=`<rect x="${x}" y="1127" width="22" height="22" rx="7" fill="${color}" stroke="#243E34" stroke-opacity=".1"/>`;
 content+=text(x+34,1143,color.slice(1),12,muted,500,'letter-spacing=".7"');
}
content+=text(1720,1172,'引导页为应用实际 Web 渲染截图',12,muted,400,'text-anchor="end"');
content+='</svg>';
const mask=Buffer.from(`<svg width="${screenW}" height="${screenH}"><rect width="${screenW}" height="${screenH}" rx="26" fill="white"/></svg>`);
(async()=>{
 const iconBackground=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="296" height="641"><rect width="296" height="641" fill="#E5EEE4"/><circle cx="148" cy="302" r="218" fill="none" stroke="#D1E2D3"/><circle cx="148" cy="302" r="164" fill="none" stroke="#D1E2D3"/>${text(148,437,'译包 LangPack',26,ink,600,'text-anchor="middle" letter-spacing="-.5"')}${text(148,604,'WORDS WITHOUT BORDERS',9,muted,400,'text-anchor="middle" letter-spacing="2"')}</svg>`);
 const icon=await sharp(path.join(base,'app-icon.svg')).resize(190,190).composite([{input:Buffer.from('<svg width="190" height="190"><rect width="190" height="190" rx="45" fill="white"/></svg>'),blend:'dest-in'}]).png().toBuffer();
 const tile=await sharp(iconBackground).composite([{input:icon,left:53,top:188},{input:mask,blend:'dest-in'}]).png().toBuffer();
 const layers=[{input:tile,left:xs[0]+6,top:top+6}];
 // The launch frame is drawn at the same proportions as splash.html.
 const splashBackground=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="296" height="641"><rect width="296" height="641" fill="#F5F8F4"/>${text(148,370,'LangPack',23,ink,700,'text-anchor="middle" letter-spacing="-.8"')}${text(148,391,'WORDS WITHOUT BORDERS',7.6,muted,400,'text-anchor="middle" letter-spacing="1.5"')}</svg>`);
 const splashIcon=await sharp(path.join(base,'app-icon.svg')).resize(73,73).composite([{input:Buffer.from('<svg width="73" height="73"><rect width="73" height="73" rx="17.5" fill="white"/></svg>'),blend:'dest-in'}]).png().toBuffer();
 const splash=await sharp(splashBackground).composite([{input:splashIcon,left:112,top:253},{input:mask,blend:'dest-in'}]).png().toBuffer();
 layers.push({input:splash,left:xs[1]+6,top:top+6});
 for(const [i,file] of ['flutter-intro-01.jpg','flutter-intro-02.jpg','flutter-intro-03.jpg'].entries()){
  const image=await sharp(path.join(base,'previews',file)).resize(screenW,screenH,{fit:'fill'}).composite([{input:mask,blend:'dest-in'}]).png().toBuffer();
  layers.push({input:image,left:xs[i+2]+6,top:top+6});
 }
 await sharp(Buffer.from(content)).composite(layers).png().toFile(path.join(base,'overview.png'));
 console.log('Saved design/brand/overview.png (1800 × 1210)');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
