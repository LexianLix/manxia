(() => {
  const root = 'https://www.peppercarrot.com';
  const books = [
    {path:'/cn/webcomics/peppercarrot.html', title:'小辣椒与萝卜头', author:'David Revoy',
      cover:root+'/0_sources/ep01_Potion-of-Flight/low-res/cn_Pepper-and-Carrot_by-David-Revoy_E01P01.jpg'},
  ];
  const clean = s => s.replace(/<[^>]+>/g,'').replace(/&amp;/g,'&').replace(/&#039;/g,"'").trim();
  return {
    discover: () => ({result: [books[0]]}),
    search: ctx => ({result: [books[0]].filter(b => [b.title,'Pepper Carrot','小辣椒','萝卜头','蘿蔔頭','David Revoy'].some(s=>s.toLowerCase().includes(ctx.query.trim().toLowerCase())))}),
    detail(ctx) {
      if (!ctx.responses.length) return {request: ctx.url};
      const chapters = [], seen = new Set();
      for (const m of ctx.responses[0].matchAll(/<figcaption[^>]*>\s*<a[^>]+href=["']([^"']+\/cn\/webcomic\/[^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
        if (!seen.has(m[1])) {seen.add(m[1]); chapters.push({path:m[1],title:clean(m[2])});}
      }
      return {result: {description:'年轻女巫小辣椒与猫萝卜头的奇幻冒险。漫画由 David Revoy 创作，中文翻译来自原站社区。作品权利与许可见原站。',chapters}};
    },
    pages(ctx) {
      if (!ctx.responses.length) return {request: ctx.url};
      const pages=[], seen=new Set();
      for (const m of ctx.responses[0].matchAll(/<img[^>]+src=["']([^"']+\/0_sources\/[^"']+\/low-res\/cn_[^"']+_E\d+P\d+\.(?:jpg|png))["']/gi)) {
        if (!/_E\d+P00\./.test(m[1]) && !seen.has(m[1])) {seen.add(m[1]); pages.push(m[1]);}
      }
      return {result: pages};
    },
  };
})()
