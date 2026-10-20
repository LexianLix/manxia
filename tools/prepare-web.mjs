import { mkdir, cp, copyFile } from 'node:fs/promises';
const output = new URL('../web/pdfjs/',import.meta.url);
const source = new URL('../node_modules/pdfjs-dist/',import.meta.url);
await mkdir(output,{recursive:true});
for(const name of ['build/pdf.mjs','build/pdf.worker.mjs','LICENSE']) {
  await copyFile(new URL(name,source),new URL(name.split('/').pop(),output));
}
for(const name of ['cmaps','standard_fonts']) await cp(new URL(name,source),new URL(name,output),{recursive:true});
console.log('Local PDF.js assets prepared.');
