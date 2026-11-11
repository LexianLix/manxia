(() => {
  function listing(ctx) {
    if (!ctx.responses.length) return {request: '/api/getsortlist/?page='+Math.max(1,ctx.page||1)+'&pagesize=40&search_key=' + encodeURIComponent(ctx.query || '')};
    const data = JSON.parse(ctx.responses[0]);
    if (data.status !== 0 || !Array.isArray(data.data)) throw Error('看漫目录暂不可用');
    return {result: data.data.slice(0, 100).map(b => ({path: '/' + b.comic_id + '/', title: b.comic_name,
      cover: String(b.cover_img || 'https://image.yqmh.com/mh/' + b.comic_id + '.jpg').replace(/^http:/, 'https:'),
      author: b.comic_author || '', latest: b.last_chapter_name || ''}))};
  }
  return {
    search: listing, discover: listing,
    detail(ctx) {
      const id=/\/(\d+)\/?$/.exec(ctx.url)?.[1];
      if(!id)throw Error('作品编号无效');
      if (!ctx.responses.length) return {request: '/api/getchapterlist/?comic_id='+id};
      const data=JSON.parse(ctx.responses[0]);
      if(data.status!==0||!Array.isArray(data.data))throw Error('看漫未返回公开章节目录');
      const seen = new Set(), chapters = [];
      for (const row of [...data.data].sort((a,b)=>Number(b.order_num||0)-Number(a.order_num||0))) {
        if(Number(row.price||0)!==0)continue;
        const slug=String(row.chapter_newid||'');
        if(!/^[a-z0-9_-]+$/i.test(slug))continue;
        const path='/'+id+'/'+slug+'.html', title=String(row.chapter_name||'').trim();
        if(title&&!seen.has(path)){seen.add(path);chapters.push({path,title});}
      }
      return {result: {description: '此来源提供原站公开章节，完整作品信息请查看原站。', chapters}};
    },
    pages(ctx) {
      if (!ctx.responses.length) return {request: ctx.url};
      // Read the public image array only; never evaluate the site's scripts.
      const match = /\bchapter_img_list\s*:\s*(\[(?:"(?:\\.|[^"\\])*"\s*,?\s*)*\])/i.exec(ctx.responses[0]);
      if (!match) throw Error('该章未公开图片，可能需要在原站登录或购买');
      const pages = JSON.parse(match[1]);
      if (!pages.length) throw Error('该章暂无公开可读图片');
      return {result: pages.map(p => p.replace(/^http:/, 'https:'))};
    },
  };
})()
