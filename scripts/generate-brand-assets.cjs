#!/usr/bin/env node
// Run with Node.js + sharp installed (or NODE_PATH pointing to its package directory).
// The checked-in SVG sources are the single source of truth for all app icons.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const dir = relative => path.join(root, relative);
const write = (relative, value) => { fs.mkdirSync(path.dirname(dir(relative)), {recursive:true}); fs.writeFileSync(dir(relative), value); };
const source = fs.readFileSync(dir('design/brand/app-icon.svg'));
const mark = fs.readFileSync(dir('design/brand/mark.svg'));
const render = async (svg, size, relative) => { fs.mkdirSync(path.dirname(dir(relative)),{recursive:true}); await sharp(svg).resize(size,size).png().toFile(dir(relative)); };
const rounded = Buffer.from(source.toString().replace('<rect width="1024" height="1024" fill="#197E64"/>', '<rect width="1024" height="1024" rx="224" fill="#197E64"/>'));
const foreground = Buffer.from(mark.toString().replace('<g id="language-cards">', '<g transform="translate(92 92) scale(.82)"><g id="language-cards">').replace('</svg>', '</g></svg>'));
(async () => {
  for (const target of ['flutter_app/assets/brand','web/assets/brand']) {
    write(target+'/app-icon.svg',source); write(target+'/mark.svg',mark);
    await render(source,1024,target+'/app-icon.png'); await render(mark,1024,target+'/mark.png');
  }
  await render(source,1024,'design/brand/app-icon.png');
  await render(mark,1024,'design/brand/mark.png');
  const ios='flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset';
  for (const image of JSON.parse(fs.readFileSync(dir(ios+'/Contents.json'))).images) {
    const size = Math.round(parseFloat(image.size)*parseFloat(image.scale));
    fs.mkdirSync(dir(ios),{recursive:true});
    await sharp(source).resize(size,size).flatten({background:'#197E64'}).removeAlpha().png().toFile(dir(ios+'/'+image.filename));
  }
  const mac='flutter_app/macos/Runner/Assets.xcassets/AppIcon.appiconset';
  // macOS keeps an optical margin inside its 1024-point icon canvas.
  const macSource=Buffer.from(rounded.toString().replace('viewBox="0 0 1024 1024"','viewBox="-80 -80 1184 1184"'));
  for (const size of [16,32,64,128,256,512,1024]) await render(macSource,size,mac+'/app_icon_'+size+'.png');
  for (const [density,size] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})) {
    await render(rounded,size,`flutter_app/android/app/src/main/res/mipmap-${density}/ic_launcher.png`);
    await render(foreground,Math.round(size*2.25),`flutter_app/android/app/src/main/res/drawable-${density}/ic_launcher_foreground.png`);
    await render(rounded,Math.round(size*2),`flutter_app/android/app/src/main/res/drawable-${density}/launch_logo.png`);
  }
  for (const size of [192,512]) {
    await render(rounded,size,`flutter_app/web/icons/Icon-${size}.png`);
    await render(source,size,`flutter_app/web/icons/Icon-maskable-${size}.png`);
  }
  await render(rounded,32,'flutter_app/web/favicon.png');
  const launch='flutter_app/ios/Runner/Assets.xcassets/LaunchImage.imageset';
  for (const scale of [1,2,3]) await render(rounded,96*scale,launch+`/LaunchImage${scale===1?'':'@'+scale+'x'}.png`);
  // ICO embeds PNG images at all supported sizes, including high DPI Windows tiles.
  const buffers=[]; for (const size of [16,24,32,48,64,128,256]) buffers.push({size,data:await sharp(rounded).resize(size,size).png().toBuffer()});
  const header=Buffer.alloc(6+16*buffers.length);header.writeUInt16LE(1,2);header.writeUInt16LE(buffers.length,4);let offset=header.length;
  buffers.forEach(({size,data},i)=>{const n=6+i*16;header[n]=size===256?0:size;header[n+1]=size===256?0:size;header.writeUInt16LE(1,n+4);header.writeUInt16LE(32,n+6);header.writeUInt32LE(data.length,n+8);header.writeUInt32LE(offset,n+12);offset+=data.length;});
  write('flutter_app/windows/runner/resources/app_icon.ico',Buffer.concat([header,...buffers.map(item=>item.data)]));
  console.log('Generated brand icons for iOS, Android, macOS, Windows and Web; launch images retained.');
})();
