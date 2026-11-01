import {createHash} from 'node:crypto';

const crcTable=Uint32Array.from({length:256},(_,value)=>{
  for(let bit=0;bit<8;bit++)value=(value&1)?0xedb88320^(value>>>1):value>>>1;
  return value>>>0;
});
function crc32(bytes) {
  let crc=0xffffffff;
  for(const byte of bytes)crc=crcTable[(crc^byte)&255]^(crc>>>8);
  return (crc^0xffffffff)>>>0;
}

export function checkCharacter(c) {
  const fail=()=>{throw new Error('Invalid character expression assets');};
  if (!c || Object.keys(c).some(k=>k!=='states') || !c.states || Array.isArray(c.states) || !c.states.idle) fail();
  const files=new Map();
  for(const [state,f] of Object.entries(c.states)) {
    if(!['idle','blink','happy','puzzled'].includes(state) || !f || Object.keys(f).some(k=>!['file','sha256'].includes(k)) ||
      !/^[a-z][a-z0-9_-]{0,30}\.png$/.test(f.file) || !/^[a-f0-9]{64}$/.test(f.sha256)) fail();
    if(files.has(f.file) && files.get(f.file)!==f.sha256) fail();
    files.set(f.file,f.sha256);
  }
}

export function checkCharacterPng(bytes) {
  if(bytes.length>256*1024 || bytes.length<33 || !bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) ||
    bytes.toString('ascii',12,16)!=='IHDR' || !bytes.readUInt32BE(16) || !bytes.readUInt32BE(20) ||
    bytes.readUInt32BE(16)>512 || bytes.readUInt32BE(20)>512) throw new Error('Character PNG must be static, <=512px and <=256 KB');
  for(let at=8;at<bytes.length;) {
    const size=bytes.readUInt32BE(at),end=at+12+size;
    if(end>bytes.length || bytes.toString('ascii',at+4,at+8)==='acTL') throw new Error('Invalid or animated PNG');
    at=end;
  }
}

/// Deterministic stored ZIP. PNGs are already compressed; no extra runtime dependency.
export function characterZip(manifest,images) {
  checkCharacter(manifest.contributes.character);
  const entries=new Map([['manifest.json',Buffer.from(JSON.stringify(manifest,null,2)+'\n')]]);
  for(const f of Object.values(manifest.contributes.character.states)) {
    const bytes=images.get(f.file);if(!bytes)throw new Error(`Missing ${f.file}`);
    checkCharacterPng(bytes);
    if(createHash('sha256').update(bytes).digest('hex')!==f.sha256)throw new Error(`Hash mismatch: ${f.file}`);
    entries.set(f.file,bytes);
  }
  const chunks=[],directory=[];let offset=0;
  for(const [name,data] of entries) {
    const filename=Buffer.from(name),checksum=crc32(data),local=Buffer.alloc(30),central=Buffer.alloc(46);
    local.writeUInt32LE(0x04034b50);local.writeUInt16LE(20,4);local.writeUInt16LE(33,12);
    local.writeUInt32LE(checksum,14);local.writeUInt32LE(data.length,18);local.writeUInt32LE(data.length,22);local.writeUInt16LE(filename.length,26);
    central.writeUInt32LE(0x02014b50);central.writeUInt16LE(20,4);central.writeUInt16LE(20,6);central.writeUInt16LE(33,14);
    central.writeUInt32LE(checksum,16);central.writeUInt32LE(data.length,20);central.writeUInt32LE(data.length,24);central.writeUInt16LE(filename.length,28);central.writeUInt32LE(offset,42);
    chunks.push(local,filename,data);directory.push(central,filename);offset+=local.length+filename.length+data.length;
  }
  const central=Buffer.concat(directory),end=Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);end.writeUInt16LE(entries.size,8);end.writeUInt16LE(entries.size,10);end.writeUInt32LE(central.length,12);end.writeUInt32LE(offset,16);
  return Buffer.concat([...chunks,central,end]);
}
