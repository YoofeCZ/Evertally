import { exportSchema, scopeFor, type ExportEnvelope, type Scope } from "./contracts";
import { worldPayload } from "./world-privacy";
export type { ExportEnvelope } from "./contracts";
export type { Scope } from "./contracts";

const MAX_BYTES=25*1024*1024;
const FORBIDDEN=new Set(["__proto__","prototype","constructor"]);

/** Parser for data-only WoW SavedVariables. Never evaluates source code. */
class SavedVariableParser{
  private index=0;
  private nodes=0;
  constructor(private readonly source:string){}
  private fail(message:string):never{throw new Error(`${message} (position ${this.index}).`);}
  private skip(){
    for(;;){
      while(/\s/.test(this.source[this.index]??"")&&this.index<this.source.length)this.index++;
      if(this.source.startsWith("--",this.index)){
        this.index+=2;
        const block=this.source.slice(this.index).match(/^\[(=*)\[/);
        if(block){const end="]"+block[1]+"]";this.index+=block[0].length;const pos=this.source.indexOf(end,this.index);if(pos<0)this.fail("Unterminated comment");this.index=pos+end.length;}
        else{while(this.index<this.source.length&&!/[\r\n]/.test(this.source[this.index]))this.index++;}
      }else break;
    }
  }
  private take(token:string){this.skip();if(!this.source.startsWith(token,this.index))this.fail(`Expected ${token}`);this.index+=token.length;}
  parse(){
    this.skip();const name=this.identifier();if(name!=="EvertallyExportDB")this.fail("Choose the Evertally_Export.lua file");this.take("=");const value=this.value(0);this.skip();if(this.source[this.index]===";"){this.index++;this.skip();}if(this.index!==this.source.length)this.fail("The file contains further statements");return value;
  }
  private identifier(){this.skip();const match=this.source.slice(this.index).match(/^[A-Za-z_][A-Za-z0-9_]*/);if(!match)this.fail("Expected an identifier");this.index+=match[0].length;return match[0];}
  private string(){
    const quote=this.source[this.index++];const bytes:number[]=[];const encoder=new TextEncoder();
    const append=(value:string)=>bytes.push(...encoder.encode(value));
    while(this.index<this.source.length){
      let c=this.source[this.index++];if(c===quote){try{return new TextDecoder("utf-8",{fatal:true}).decode(new Uint8Array(bytes));}catch{this.fail("String is not valid UTF-8");}}
      if(c==="\n"||c==="\r")this.fail("Unescaped newline in string");
      if(c!=="\\"){if(/[\uD800-\uDBFF]/.test(c)&&/[\uDC00-\uDFFF]/.test(this.source[this.index]??""))c+=this.source[this.index++];append(c);continue;}
      const escape=this.source[this.index++];const map:Record<string,string>={a:"\x07",b:"\b",f:"\f",n:"\n",r:"\r",t:"\t",v:"\v","\\":"\\",'"':'"',"'":"'"};
      if(escape in map){append(map[escape]);continue;}
      if(escape==="\n"){bytes.push(10);continue;}
      if(escape==="\r"){if(this.source[this.index]==="\n")this.index++;bytes.push(10);continue;}
      if(/[0-9]/.test(escape??"")){let digits=escape;while(digits.length<3&&/[0-9]/.test(this.source[this.index]??""))digits+=this.source[this.index++];const byte=Number(digits);if(byte>255)this.fail("Invalid escape sequence");bytes.push(byte);continue;}
      this.fail("Escape sequence not allowed");
    }
    this.fail("Unterminated string");
  }
  private value(depth:number):unknown{
    if(depth>40||++this.nodes>400000)this.fail("Structure limit exceeded");this.skip();const c=this.source[this.index];
    if(c==='"'||c==="'")return this.string();
    if(c==="{")return this.table(depth+1);
    for(const [word,value] of [["true",true],["false",false],["nil",null]] as const){if(this.source.startsWith(word,this.index)&&!/[A-Za-z0-9_]/.test(this.source[this.index+word.length]??"")){this.index+=word.length;return value;}}
    const match=this.source.slice(this.index).match(/^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/);if(match){this.index+=match[0].length;const n=Number(match[0]);if(!Number.isFinite(n))this.fail("Number is not finite");return n;}
    this.fail("Only data is allowed, not Lua statements or functions");
  }
  private table(depth:number):unknown{
    this.take("{");const entries=new Map<string|number,unknown>();let autoIndex=1;let explicitString=false;
    for(;;){this.skip();if(this.source[this.index]==="}"){this.index++;break;}
      let key:string|number,value:unknown;
      if(this.source[this.index]==="["){
        this.index++;const k=this.value(depth);if(typeof k!=="string"&&typeof k!=="number")this.fail("Invalid table key");key=k;this.take("]");this.take("=");value=this.value(depth);
      }else{
        const saved=this.index;const ident=this.source.slice(this.index).match(/^[A-Za-z_][A-Za-z0-9_]*/);
        if(ident){this.index+=ident[0].length;this.skip();if(this.source[this.index]==="="){this.index++;key=ident[0];value=this.value(depth);}else{this.index=saved;key=autoIndex++;value=this.value(depth);}}
        else{key=autoIndex++;value=this.value(depth);}
      }
      if(typeof key==="string"){if(FORBIDDEN.has(key))this.fail("Forbidden key");explicitString=true;}
      else if(!Number.isInteger(key)||key<1||key>100000)this.fail("Invalid numeric index");
      if(entries.has(key))this.fail("Duplicate key");entries.set(key,value);
      this.skip();if(this.source[this.index]===","||this.source[this.index]===";"){this.index++;continue;}if(this.source[this.index]!=="}")this.fail("Expected a comma or end of table");
    }
    if(!explicitString){const array:unknown[]=[];for(let i=1;i<=entries.size;i++){if(!entries.has(i))this.fail("Sparse arrays are not supported");array.push(entries.get(i));}return array;}
    const object=Object.create(null) as Record<string,unknown>;for(const [key,val]of entries){if(typeof key!=="string")this.fail("Mixed tables are not supported");if(val!==null)object[key]=val;}return object;
  }
}

/** Accept JSON or exactly one data-only EvertallyExportDB assignment. */
export function parseExport(text:string):ExportEnvelope{
  if(new TextEncoder().encode(text).byteLength>MAX_BYTES)throw new Error("The export exceeds the 25 MiB limit.");
  const source=text.replace(/^\uFEFF/,"").trim();
  if(!source)throw new Error("The file is empty.");
  let value:unknown;
  try{value=source.startsWith("{")?JSON.parse(source):new SavedVariableParser(source).parse();}catch(error){throw new Error(`Cannot read the export: ${error instanceof Error?error.message:"invalid format"}`);}
  // Local-only metadata is for the live bridge; manual/community history imports never forward contacts.
  if(value&&typeof value==="object"&&!Array.isArray(value))delete (value as Record<string,unknown>).connections;
  const parsed=exportSchema.safeParse(value);
  if(!parsed.success)throw new Error(`Invalid export: ${parsed.error.issues.slice(0,3).map(issue=>`${issue.path.join(".")}: ${issue.message}`).join("; ")}`);
  return parsed.data;
}

/** Build the only uploadable projection in the browser before any network call. */
export function projectExport(value:ExportEnvelope,scopes:Scope[]):ExportEnvelope{
  // The guild recognises members by character name, so it cannot be shared without the character scope.
  const selected=[...new Set(scopes)].filter(scope=>value.scopes.includes(scope)&&(scope!=="guild_share"||scopes.includes("own_character")));
  const includeCharacter=selected.includes("own_character");
  return {...value,scopes:selected,events:value.events.filter(event=>selected.includes(scopeFor(event.kind))).map(event=>{
    const {character,...source}=event;
    const rest={...source,payload:scopeFor(event.kind)==="world_facts"?worldPayload(event.kind,event.payload):event.payload};
    if(includeCharacter)return {...rest,...(character?{character:{...character}}:{})};
    if((scopeFor(event.kind)==="own_runs"||scopeFor(event.kind)==="own_track")&&character){
      if(scopeFor(event.kind)==="own_runs"){
        rest.payload={...rest.payload};delete rest.payload.roster;
        const combat=rest.payload.combat as Record<string,unknown>|undefined;
        if(combat&&typeof combat==="object"){
          const players=Array.isArray(combat.players)?combat.players as Record<string,unknown>[]:[];
          rest.payload.combat={...combat,players:players.filter(p=>p.guid===character.id).map(p=>{const clean:Record<string,unknown>={...p,guid:value.producerId+":own"};delete clean.name;return clean;})};
        }
      }
      return {...rest,character:{id:value.producerId+":own",...(character.classId!==undefined?{classId:character.classId}:{}),...(character.raceId!==undefined?{raceId:character.raceId}:{}),...(character.level!==undefined?{level:character.level}:{})}};
    }
    return rest;
  })};
}
