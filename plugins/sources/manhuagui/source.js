(() => {
/* lz-string 1.5.0, https://github.com/pieroxy/lz-string
MIT License

Copyright (c) 2013 pieroxy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/
var LZString=function(){var r=String.fromCharCode,o="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",n="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$",e={};function t(r,o){if(!e[r]){e[r]={};for(var n=0;n<r.length;n++)e[r][r.charAt(n)]=n}return e[r][o]}var i={compressToBase64:function(r){if(null==r)return"";var n=i._compress(r,6,function(r){return o.charAt(r)});switch(n.length%4){default:case 0:return n;case 1:return n+"===";case 2:return n+"==";case 3:return n+"="}},decompressFromBase64:function(r){return null==r?"":""==r?null:i._decompress(r.length,32,function(n){return t(o,r.charAt(n))})},compressToUTF16:function(o){return null==o?"":i._compress(o,15,function(o){return r(o+32)})+" "},decompressFromUTF16:function(r){return null==r?"":""==r?null:i._decompress(r.length,16384,function(o){return r.charCodeAt(o)-32})},compressToUint8Array:function(r){for(var o=i.compress(r),n=new Uint8Array(2*o.length),e=0,t=o.length;e<t;e++){var s=o.charCodeAt(e);n[2*e]=s>>>8,n[2*e+1]=s%256}return n},decompressFromUint8Array:function(o){if(null==o)return i.decompress(o);for(var n=new Array(o.length/2),e=0,t=n.length;e<t;e++)n[e]=256*o[2*e]+o[2*e+1];var s=[];return n.forEach(function(o){s.push(r(o))}),i.decompress(s.join(""))},compressToEncodedURIComponent:function(r){return null==r?"":i._compress(r,6,function(r){return n.charAt(r)})},decompressFromEncodedURIComponent:function(r){return null==r?"":""==r?null:(r=r.replace(/ /g,"+"),i._decompress(r.length,32,function(o){return t(n,r.charAt(o))}))},compress:function(o){return i._compress(o,16,function(o){return r(o)})},_compress:function(r,o,n){if(null==r)return"";var e,t,i,s={},u={},a="",p="",c="",l=2,f=3,h=2,d=[],m=0,v=0;for(i=0;i<r.length;i+=1)if(a=r.charAt(i),Object.prototype.hasOwnProperty.call(s,a)||(s[a]=f++,u[a]=!0),p=c+a,Object.prototype.hasOwnProperty.call(s,p))c=p;else{if(Object.prototype.hasOwnProperty.call(u,c)){if(c.charCodeAt(0)<256){for(e=0;e<h;e++)m<<=1,v==o-1?(v=0,d.push(n(m)),m=0):v++;for(t=c.charCodeAt(0),e=0;e<8;e++)m=m<<1|1&t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t>>=1}else{for(t=1,e=0;e<h;e++)m=m<<1|t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t=0;for(t=c.charCodeAt(0),e=0;e<16;e++)m=m<<1|1&t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t>>=1}0==--l&&(l=Math.pow(2,h),h++),delete u[c]}else for(t=s[c],e=0;e<h;e++)m=m<<1|1&t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t>>=1;0==--l&&(l=Math.pow(2,h),h++),s[p]=f++,c=String(a)}if(""!==c){if(Object.prototype.hasOwnProperty.call(u,c)){if(c.charCodeAt(0)<256){for(e=0;e<h;e++)m<<=1,v==o-1?(v=0,d.push(n(m)),m=0):v++;for(t=c.charCodeAt(0),e=0;e<8;e++)m=m<<1|1&t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t>>=1}else{for(t=1,e=0;e<h;e++)m=m<<1|t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t=0;for(t=c.charCodeAt(0),e=0;e<16;e++)m=m<<1|1&t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t>>=1}0==--l&&(l=Math.pow(2,h),h++),delete u[c]}else for(t=s[c],e=0;e<h;e++)m=m<<1|1&t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t>>=1;0==--l&&(l=Math.pow(2,h),h++)}for(t=2,e=0;e<h;e++)m=m<<1|1&t,v==o-1?(v=0,d.push(n(m)),m=0):v++,t>>=1;for(;;){if(m<<=1,v==o-1){d.push(n(m));break}v++}return d.join("")},decompress:function(r){return null==r?"":""==r?null:i._decompress(r.length,32768,function(o){return r.charCodeAt(o)})},_decompress:function(o,n,e){var t,i,s,u,a,p,c,l=[],f=4,h=4,d=3,m="",v=[],g={val:e(0),position:n,index:1};for(t=0;t<3;t+=1)l[t]=t;for(s=0,a=Math.pow(2,2),p=1;p!=a;)u=g.val&g.position,g.position>>=1,0==g.position&&(g.position=n,g.val=e(g.index++)),s|=(u>0?1:0)*p,p<<=1;switch(s){case 0:for(s=0,a=Math.pow(2,8),p=1;p!=a;)u=g.val&g.position,g.position>>=1,0==g.position&&(g.position=n,g.val=e(g.index++)),s|=(u>0?1:0)*p,p<<=1;c=r(s);break;case 1:for(s=0,a=Math.pow(2,16),p=1;p!=a;)u=g.val&g.position,g.position>>=1,0==g.position&&(g.position=n,g.val=e(g.index++)),s|=(u>0?1:0)*p,p<<=1;c=r(s);break;case 2:return""}for(l[3]=c,i=c,v.push(c);;){if(g.index>o)return"";for(s=0,a=Math.pow(2,d),p=1;p!=a;)u=g.val&g.position,g.position>>=1,0==g.position&&(g.position=n,g.val=e(g.index++)),s|=(u>0?1:0)*p,p<<=1;switch(c=s){case 0:for(s=0,a=Math.pow(2,8),p=1;p!=a;)u=g.val&g.position,g.position>>=1,0==g.position&&(g.position=n,g.val=e(g.index++)),s|=(u>0?1:0)*p,p<<=1;l[h++]=r(s),c=h-1,f--;break;case 1:for(s=0,a=Math.pow(2,16),p=1;p!=a;)u=g.val&g.position,g.position>>=1,0==g.position&&(g.position=n,g.val=e(g.index++)),s|=(u>0?1:0)*p,p<<=1;l[h++]=r(s),c=h-1,f--;break;case 2:return v.join("")}if(0==f&&(f=Math.pow(2,d),d++),l[c])m=l[c];else{if(c!==h)return null;m=i+i.charAt(0)}v.push(m),l[h++]=i+m.charAt(0),i=m,0==--f&&(f=Math.pow(2,d),d++)}}};return i}();"function"==typeof define&&define.amd?define(function(){return LZString}):"undefined"!=typeof module&&null!=module?module.exports=LZString:"undefined"!=typeof angular&&null!=angular&&angular.module("LZString",[]).factory("LZString",function(){return LZString});
  const text = s => String(s || '').replace(/<[^>]*>/g,'').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").trim();
  const attr = (tag,key) => (new RegExp('\\b'+key+'=["\']([^"\']*)["\']','i').exec(tag)||[])[1]||'';
  const image = s => s.startsWith('//') ? 'https:'+s : s;
  function listing(ctx) {
    const page=Math.max(1,ctx.page||1);
    if (!ctx.responses.length) return {request:ctx.query ? '/s/'+encodeURIComponent(ctx.query)+'_p'+page+'.html' : '/list/view_p'+page+'.html'};
    const books=[], seen=new Set();
    for (const m of ctx.responses[0].matchAll(/<li\b[^>]*>([\s\S]*?)<\/li>/gi)) {
      const a=/<a\b([^>]*href=["']\/comic\/\d+\/["'][^>]*)>/i.exec(m[1]);
      const img=/<img\b([^>]*)>/i.exec(m[1]);
      if (!a || !img) continue;
      const path=attr(a[1],'href'), title=text(attr(a[1],'title') || attr(img[1],'alt'));
      const cover=image(attr(img[1],'data-src') || attr(img[1],'src'));
      if (title && cover && !seen.has(path)) {seen.add(path);books.push({path,title,cover});}
    }
    return {result:books.slice(0,100)};
  }
  function pages(body) {
    // Decode only the packed string/dictionary data. No eval or site code runs.
    const m=/\}\s*\(\s*'((?:\\.|[^'\\])*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'([^']*)'/.exec(body);
    if (!m) throw Error('漫画柜未返回公开图片列表，可能已移除或需要验证');
    const payload=m[1].replace(/\\'/g,"'").replace(/\\\\/g,'\\');
    const dictionary=LZString.decompressFromBase64(m[4]);
    if (!dictionary || dictionary.length>300000) throw Error('漫画柜图片字典无效');
    const words=dictionary.split('|'), base=Number(m[2]);
    if(base<2 || base>62 || Number(m[3])>10000) throw Error('漫画柜图片编码无效');
    const digits='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const unpacked=payload.replace(/\b[0-9a-zA-Z]+\b/g, token=>{
      let index=0;for(const ch of token){const n=digits.indexOf(ch);if(n<0||n>=base)return token;index=index*base+n;if(index>10000)return token;}
      return words[index] || token;
    });
    const start=unpacked.indexOf('{'), end=unpacked.lastIndexOf('}');
    const data=JSON.parse(unpacked.slice(start,end+1));
    if(!Array.isArray(data.files)||!data.path||!data.sl)throw Error('漫画柜图片字段不完整');
    return data.files.map(f=>'https://i.hamreus.com'+data.path+f+'?e='+encodeURIComponent(data.sl.e)+'&m='+encodeURIComponent(data.sl.m));
  }
  return {
    search:listing, discover:listing,
    detail(ctx) {
      if(!ctx.responses.length)return {request:ctx.url};
      const body=ctx.responses[0], chapters=[],seen=new Set();
      const bookId=/\/comic\/(\d+)/.exec(ctx.url)?.[1];
      const groups=[...body.matchAll(/<div[^>]+id=["']chapter-list-\d+["'][^>]*>([\s\S]*?)<\/div>/gi)];
      for(let g=0;g<groups.length;g++){
        const lists=[...groups[g][1].matchAll(/<ul\b[^>]*>([\s\S]*?)<\/ul>/gi)].reverse();
        for(const ul of lists)for(const a of ul[1].matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)){
          const path=attr(a[1],'href'), title=text(attr(a[1],'title')||a[2]);
          if(path.startsWith('/comic/'+bookId+'/')&&/\.html$/.test(path)&&title&&!seen.has(path)){
            seen.add(path);chapters.push({path,title,group:groups.length>1?(g===0?'单话':'单行本'):'连载'});
          }
        }
      }
      const intro=/<div[^>]+id=["']intro-all["'][^>]*>([\s\S]*?)<\/div>/i.exec(body);
      return {result:{description:text(intro?.[1]),chapters}};
    },
    pages(ctx){return !ctx.responses.length?{request:ctx.url}:{result:pages(ctx.responses[0])};},
  };

})()
