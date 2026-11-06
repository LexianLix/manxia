(() => {
  const index = 'assets/characters/index.json';
  const folder = 'assets/characters/xiaxia/';
  const book = {
    path: `${index}?book=xiaxia`, title: '漫匣试读', author: 'Manxia',
    cover: `${folder}idle.png`,
  };
  const chapter = {path: `${index}?chapter=1`, title: '第1话 小夏的阅读室'};

  function read(ctx, select) {
    if (ctx.responses.length === 0) return {request: index};
    const images = Object.values(JSON.parse(ctx.responses[0]).images);
    return {result: select(images)};
  }

  return {
    search(ctx) {
      const query = ctx.query.trim().toLowerCase();
      const matches = [book.title, '漫匣試讀', '小夏', 'Manxia Demo']
        .some(title => title.toLowerCase().includes(query));
      return read(ctx, images => matches && images.includes(book.cover) ? [book] : []);
    },
    detail(ctx) {
      return read(ctx, images => ({
        description: '小夏的三张表情卡，供测试搜索、目录和阅读。',
        chapters: ctx.url === ctx.baseUrl + book.path && images.includes(book.cover) ? [chapter] : [],
      }));
    },
    pages(ctx) {
      return read(ctx, images => ctx.url === ctx.baseUrl + chapter.path
        ? ['idle', 'happy', 'blink'].map(name => `${folder}${name}.png`).filter(path => images.includes(path))
        : []);
    },
  };
})()
