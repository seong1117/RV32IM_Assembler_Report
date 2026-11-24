#include <cmath>
#include <cstring>
#include <limits>
// RV32IM course assembler. Build: g++ -std=c++17 -O2 rv32asm.cpp -o rv32asm
#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;
using N = int64_t;
using U = uint32_t;
constexpr N START=0x10000, STACK=0x40000, LIMIT=0x04000000;
struct Line { int no; string raw,label,op; vector<string> a; int sec=0; N pc=0,size=0; };
struct Sym { N value; char type; };
using Symbols=map<string,Sym>;
[[noreturn]] void fail(const string& s){throw runtime_error(s);}
string trim(const string& s){auto a=s.find_first_not_of(" \t\r\n");return a==string::npos?"":s.substr(a,s.find_last_not_of(" \t\r\n")-a+1);}
bool name(const string& s){return !s.empty() && !isdigit((unsigned char)s[0]) && all_of(s.begin(),s.end(),[](unsigned char c){return isalnum(c)||c=='_'||c=='.';});}
// Find delimiters only outside quoted strings and character literals.
size_t outside(const string& s,char stop){char q=0;for(size_t i=0;i<s.size();++i){char c=s[i];if(q){if(c=='\\' && i+1<s.size())++i;else if(c==q)q=0;}else if(c==stop)return i;else if(c=='\''||c=='"')q=c;}if(q)fail("unterminated quote");return string::npos;}
Line parse(int n,string raw){Line l{};l.no=n;l.raw=raw;string s=trim(raw.substr(0,outside(raw,'#')));auto p=outside(s,':');if(p!=string::npos){l.label=trim(s.substr(0,p));if(!name(l.label))fail("invalid label: "+l.label);s=trim(s.substr(p+1));}p=s.find_first_of(" \t");l.op=s.substr(0,p);if(p!=string::npos){s=trim(s.substr(p));while(!s.empty()){p=outside(s,',');string x=trim(s.substr(0,p));if(x.empty())fail("empty operand");l.a.push_back(x);if(p==string::npos)break;s=trim(s.substr(p+1));if(s.empty())fail("missing operand after comma");}}return l;}
string decode_literal(const string& s,char q){if(s.size()<2||s.front()!=q||s.back()!=q)fail("invalid literal: "+s);string out;for(size_t i=1;i+1<s.size();++i){char c=s[i];if(c==q)fail("unexpected quote: "+s);if(c=='\\'){if(++i>=s.size()-1)fail("incomplete escape");switch(s[i]){case 'b':c='\b';break;case 'n':c='\n';break;case 't':c='\t';break;case 'r':c='\r';break;case '0':c=0;break;case '\\':case '"':case '\'':c=s[i];break;default:fail("unsupported escape in "+s);}}out+=c;}return out;}
N check(N n,N lo,N hi,const string& what){if(n<lo||n>hi)fail(what+" out of range: "+to_string(n));return n;}
N number(const string& s){if(!s.empty()&&s.front()=='\''){auto t=decode_literal(s,'\'');if(t.size()!=1)fail("character literal must be one byte");return (unsigned char)t[0];}size_t p=0;bool neg=false;if(p<s.size()&&(s[p]=='-'||s[p]=='+'))neg=s[p++]=='-';int base=10;if(p+1<s.size()&&s[p]=='0'){if(s[p+1]=='x'||s[p+1]=='X')base=16;if(s[p+1]=='b'||s[p+1]=='B')base=2;if(base!=10)p+=2;}if(p==s.size())fail("expected number: "+s);N v=0;for(;p<s.size();++p){char c=s[p];int d=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:99;if(d>=base)fail("invalid number: "+s);v=v*base+d;if(v>0xffffffffLL)fail("number exceeds 32 bits: "+s);}return neg?-v:v;}
// Constant expressions, from lowest to highest precedence.
struct Expr {
 const string& s; const Symbols& sy; size_t p=0;
 void ws(){while(p<s.size() && isspace((unsigned char)s[p]))++p;}
 bool eat(const string& t){ws();if(s.compare(p,t.size(),t)!=0)return false;p+=t.size();return true;}
 N atom(){
  if(eat("+"))return atom();
  if(eat("-")){N x=atom(), y;if(__builtin_sub_overflow(N(0),x,&y))fail("expression overflow: "+s);return y;}
  if(eat("~"))return ~atom();
  for(const string op:{"%hi","%lo"})if(eat(op)){
   if(!eat("("))fail("expected '(' after "+op);
   N x=check(eval(0),-2147483648LL,0xffffffffLL,op);
   if(!eat(")"))fail("expected ')' after "+op);
   N low=U(x)&4095;if(low>=2048)low-=4096;
   return op=="%lo"?low:((x-low)/4096)&0xfffff;
  }
  if(eat("(")){N x=eval(0);if(!eat(")"))fail("expected ')' in "+s);return x;}
  ws();size_t b=p;
  if(p<s.size() && s[p]=='\''){
   ++p;while(p<s.size()){char c=s[p++];if(c=='\'')break;if(c=='\\' && p<s.size())++p;}
  }else while(p<s.size()&&(isalnum((unsigned char)s[p])||s[p]=='_'||s[p]=='.'))++p;
  if(p==b)fail("expected expression operand: "+s);
  auto t=s.substr(b,p-b);
  if(name(t)){auto i=sy.find(t);if(i==sy.end())fail("undefined symbol: "+t);return i->second.value;}
  return number(t);
 }
 N eval(size_t level){
  static const vector<vector<string>> ops={{"|"},{"^"},{"&"},{"<<",">>"},{"+","-"},{"*","/","%"}};
  if(level==ops.size())return atom();
  N a=eval(level+1);
  for(;;){
   string op;for(const auto& t:ops[level])if(eat(t)){op=t;break;}
   if(op.empty())return a;
   N b=eval(level+1), r=0;bool overflow=false;
   if(op=="+")overflow=__builtin_add_overflow(a,b,&r);
   else if(op=="-")overflow=__builtin_sub_overflow(a,b,&r);
   else if(op=="*")overflow=__builtin_mul_overflow(a,b,&r);
   else if(op=="/"||op=="%"){if(!b)fail("division by zero: "+s);if(a==INT64_MIN&&b==-1)overflow=true;else r=op=="/"?a/b:a%b;}
   else if(op=="<<"||op==">>"){check(b,0,62,"expression shift");N k=N(1)<<b;if(op=="<<")overflow=__builtin_mul_overflow(a,k,&r);else r=a/k-(a<0 && a%k!=0);}
   else if(op=="|")r=a|b;
   else if(op=="^")r=a^b;
   else r=a&b;
   if(overflow)fail("expression overflow: "+s);
   a=r;
  }
 }
};
N value(const string& s,const Symbols& sy){Expr e{s,sy};N x=e.eval(0);e.ws();if(e.p!=s.size())fail("invalid expression: "+s);return x;}
void count(const Line& l,size_t n){if(l.a.size()!=n)fail(l.op+" expects "+to_string(n)+" operand(s)");}
U reg(const string& s){static const string abi[]={"zero","ra","sp","gp","tp","t0","t1","t2","s0","s1","a0","a1","a2","a3","a4","a5","a6","a7","s2","s3","s4","s5","s6","s7","s8","s9","s10","s11","t3","t4","t5","t6"};if(s=="fp")return 8;for(U i=0;i<32;++i)if(s==abi[i]||s=="x"+to_string(i))return i;fail("invalid register: "+s);}
U csr(const string& s,const Symbols& sy){static const map<string,U> m={{"fflags",1},{"frm",2},{"fcsr",3},{"mstatus",0x300},{"mie",0x304},{"mtvec",0x305},{"mscratch",0x340},{"mepc",0x341},{"mcause",0x342},{"mtval",0x343},{"mip",0x344},{"mhartid",0xf14}};auto i=m.find(s);return i==m.end()?check(value(s,sy),0,4095,"CSR"):i->second;}
U I(U op,U d,U f,U s,U x){return ((x&4095)<<20)|(s<<15)|(f<<12)|(d<<7)|op;}
U upper(U op,U d,U x){return ((x&0xfffff)<<12)|(d<<7)|op;}
bool small(N x){return x>=-2048&&x<=2047;}
N align_up(N x,N a){return (x+a-1)&~(a-1);}
U freg(const string& s){
 for(U i=0;i<32;++i)if(s=="f"+to_string(i))return i;
 for(U i=0;i<8;++i){if(s=="fa"+to_string(i))return 10+i;if(s=="ft"+to_string(i))return i;}
 for(U i=8;i<12;++i)if(s=="ft"+to_string(i))return 20+i;
 for(U i=0;i<12;++i)if(s=="fs"+to_string(i))return i<2?8+i:16+i;
 fail("invalid floating register: "+s);
}

vector<U> encode(Line l,const Symbols& sy){auto& a=l.a;auto& o=l.op;auto c=[&](size_t n){count(l,n);};auto v=[&](size_t j){return value(a.at(j),sy);};auto r=[&](size_t j){return reg(a.at(j));};
 auto f=[&](size_t j){return freg(a.at(j));};
 auto rm=[&](size_t n)->U{if(a.size()==n)return 7;c(n+1);static const map<string,U> m={{"rne",0},{"rtz",1},{"rdn",2},{"rup",3},{"rmm",4},{"dyn",7}};auto i=m.find(a[n]);if(i==m.end())fail("invalid rounding mode: "+a[n]);return i->second;};
 auto fp=[](U fn,U d,U s,U t,U mode){return fn<<25|t<<20|s<<15|mode<<12|d<<7|0x53;};
 if(o=="flw"||o=="fsw"){c(2);auto p=a[1].rfind('(');if(p==string::npos||a[1].back()!=')')fail("expected imm(register)");auto imm=trim(a[1].substr(0,p));U x=imm.empty()?0:check(value(imm,sy),-2048,2047,"memory immediate");x&=4095;U base=reg(trim(a[1].substr(p+1,a[1].size()-p-2)));if(o=="flw")return {I(7,f(0),2,base,x)};return {(x>>5)<<25|f(0)<<20|base<<15|2<<12|(x&31)<<7|0x27};}
 static const map<string,U> far={{"fadd.s",0},{"fsub.s",4},{"fmul.s",8},{"fdiv.s",12}};
 if(auto i=far.find(o);i!=far.end()){U m=rm(3);return {fp(i->second,f(0),f(1),f(2),m)};}
 if(o=="fsqrt.s"){U m=rm(2);return {fp(44,f(0),f(1),0,m)};}
 static const map<string,U> fma={{"fmadd.s",0x43},{"fmsub.s",0x47},{"fnmsub.s",0x4b},{"fnmadd.s",0x4f}};
 if(auto i=fma.find(o);i!=fma.end()){U m=rm(4);return {f(3)<<27|f(2)<<20|f(1)<<15|m<<12|f(0)<<7|i->second};}
 if(o=="fmin.s"||o=="fmax.s"){c(3);return {fp(20,f(0),f(1),f(2),o=="fmax.s")};}
 if(o=="feq.s"||o=="flt.s"||o=="fle.s"){c(3);return {fp(80,r(0),f(1),f(2),o=="feq.s"?2:o=="flt.s"?1:0)};}
 if(o=="fcvt.w.s"||o=="fcvt.wu.s"){U m=rm(2);return {fp(96,r(0),f(1),o=="fcvt.wu.s",m)};}
 if(o=="fcvt.s.w"||o=="fcvt.s.wu"){U m=rm(2);return {fp(104,f(0),r(1),o=="fcvt.s.wu",m)};}
 if(o=="fmv.x.w"||o=="fclass.s"){c(2);return {fp(112,r(0),f(1),0,o=="fclass.s")};}
 if(o=="fmv.w.x"){c(2);return {fp(120,f(0),r(1),0,0)};}
 if(o=="fsgnj.s"||o=="fsgnjn.s"||o=="fsgnjx.s"){c(3);return {fp(16,f(0),f(1),f(2),o=="fsgnj.s"?0:o=="fsgnjn.s"?1:2)};}
 if(o=="fmv.s"||o=="fneg.s"||o=="fabs.s"){c(2);return {fp(16,f(0),f(1),f(1),o=="fmv.s"?0:o=="fneg.s"?1:2)};}
 if(o=="li"||o=="la"){c(2);U d=r(0);N x=v(1);if(o=="li"){check(x,-2147483648LL,0xffffffffLL,"li immediate");if(small(x))return {I(0x13,d,0,0,x)};}else{x-=l.pc;check(x,-2147483648LL,2147483647LL,"la displacement");}N lo=(x+2048)%4096;if(lo<0)lo+=4096;lo-=2048;return {upper(o=="li"?0x37:0x17,d,(x-lo)/4096),I(0x13,d,0,d,lo)};}
 if(o=="nop"){c(0);o="addi";a={"zero","zero","0"};}
 else if(o=="mv"||o=="not"||o=="neg"){c(2);if(o=="neg"){o="sub";a.insert(a.begin()+1,"zero");}else{a.push_back(o=="mv"?"0":"-1");o=o=="mv"?"addi":"xori";}}
 else if(o=="ret"||o=="jr"){if(o=="ret"){c(0);a={"ra"};}else c(1);a={"zero","0("+a[0]+")"};o="jalr";}
 else if(o=="j"||o=="call"||(o=="jal"&&a.size()==1)){c(1);a.insert(a.begin(),o=="j"?"zero":"ra");o="jal";}
 else if(o=="beqz"||o=="bnez"){c(2);a.insert(a.begin()+1,"zero");o=o=="beqz"?"beq":"bne";}
 else if(o=="bgt"||o=="ble"||o=="bgtu"||o=="bleu"){c(3);swap(a[0],a[1]);o=o=="bgt"?"blt":o=="ble"?"bge":o=="bgtu"?"bltu":"bgeu";}
 else if(o=="csrr"){c(2);a.push_back("zero");o="csrrs";}
 else if(o=="csrw"||o=="csrsi"||o=="csrci"||o=="csrwi"||o=="csrs"||o=="csrc"){c(2);a.insert(a.begin(),"zero");o.insert(3,"r");}
 else if(o=="seqz"||o=="snez"||o=="sltz"||o=="sgtz"){c(2);if(o=="seqz"){o="sltiu";a.push_back("1");}else if(o=="sltz"){o="slt";a.push_back("zero");}else{ o=o=="snez"?"sltu":"slt";a.insert(a.begin()+1,"zero");}}
 else if(o=="bltz"||o=="bgez"||o=="bgtz"||o=="blez"){c(2);if(o=="bltz"||o=="bgez")a.insert(a.begin()+1,"zero");else a.insert(a.begin(),"zero");o=o=="bltz"||o=="bgtz"?"blt":"bge";}
 static const map<string,U> rr={{"add",0},{"sub",256},{"sll",1},{"slt",2},{"sltu",3},{"xor",4},{"srl",5},{"sra",261},{"or",6},{"and",7},{"mul",8},{"mulh",9},{"mulhsu",10},{"mulhu",11},{"div",12},{"divu",13},{"rem",14},{"remu",15}};
 if(auto it=rr.find(o);it!=rr.end()){c(3);U f=it->second;return {((f>>3)<<25)|(r(2)<<20)|(r(1)<<15)|((f&7)<<12)|(r(0)<<7)|0x33};}
 static const map<string,U> ii={{"addi",0},{"slti",2},{"sltiu",3},{"xori",4},{"ori",6},{"andi",7},{"slli",1},{"srli",5},{"srai",5}};
 if(auto it=ii.find(o);it!=ii.end()){c(3);bool sh=o=="slli"||o=="srli"||o=="srai";U x=sh?check(v(2),0,31,"shift amount"):check(v(2),-2048,2047,"immediate");return {I(0x13,r(0),it->second,r(1),x|(o=="srai"?0x400:0))};}
 static const map<string,U> mem={{"lb",0},{"lh",1},{"lw",2},{"lbu",4},{"lhu",5},{"sb",8},{"sh",9},{"sw",10},{"jalr",16}};
 if(auto it=mem.find(o);it!=mem.end()){if(o=="jalr"&&a.size()==3)a={a[0],a[2]+"("+a[1]+")"};c(2);auto p=a[1].rfind('(');if(p==string::npos||a[1].back()!=')')fail("expected imm(register)");string imm=trim(a[1].substr(0,p));U x=imm.empty()?0:check(value(imm,sy),-2048,2047,"memory immediate");x&=4095;U s=reg(trim(a[1].substr(p+1,a[1].size()-p-2))), f=it->second;if(f>=8&&f<16)return {((x>>5)<<25)|(r(0)<<20)|(s<<15)|((f&7)<<12)|((x&31)<<7)|0x23};return {I(f==16?0x67:3,r(0),f&7,s,x)};}
 auto disp=[&](size_t j,N lo,N hi){N x=v(j);if(name(a[j]) && sy.at(a[j]).type!='=')x-=l.pc;check(x,lo,hi,"PC-relative offset");if(x%2)fail("PC-relative offset must be even");return U(x);};
 static const map<string,U> br={{"beq",0},{"bne",1},{"blt",4},{"bge",5},{"bltu",6},{"bgeu",7}};
 if(auto it=br.find(o);it!=br.end()){c(3);U x=disp(2,-4096,4094);return {((x&0x1000)<<19)|((x&0x7e0)<<20)|(r(1)<<20)|(r(0)<<15)|(it->second<<12)|((x&0x1e)<<7)|((x&0x800)>>4)|0x63};}
 if(o=="jal"){c(2);U x=disp(1,-1048576,1048574);return {((x&0x100000)<<11)|((x&0x7fe)<<20)|((x&0x800)<<9)|(x&0xff000)|(r(0)<<7)|0x6f};}
 if(o=="lui"||o=="auipc"){c(2);return {upper(o=="lui"?0x37:0x17,r(0),check(v(1),-524288,1048575,"20-bit immediate"))};}
 static const map<string,U> fixed={{"ecall",0x73},{"ebreak",0x100073},{"fence",0x0ff0000f},{"mret",0x30200073},{"wfi",0x10500073}};
 if(auto it=fixed.find(o);it!=fixed.end()){c(0);return {it->second};}
 static const map<string,U> cs={{"csrrw",1},{"csrrs",2},{"csrrc",3},{"csrrwi",5},{"csrrsi",6},{"csrrci",7}};
 if(auto it=cs.find(o);it!=cs.end()){c(3);U f=it->second;return {I(0x73,r(0),f,f>=5?check(v(2),0,31,"CSR immediate"):r(2),csr(a[1],sy))};}
 fail("unsupported instruction: "+o);
}
int width(const string& o){return o==".byte"?1:o==".half"?2:o==".word"||o==".float"?4:o==".dword"||o==".double"?8:0;}
string strings(const Line& l){if(l.a.empty())fail("missing string operand");string s;for(const auto& a:l.a){s+=decode_literal(a,'"');if(l.op==".asciz")s+='\0';}return s;}
struct Preprocessor {
 struct Macro{vector<string> params, body;};
 map<string,Macro> macros; vector<string> out; size_t serial=0, steps=0;
 static bool id(char c){return isalnum((unsigned char)c)||c=='_'||c=='.';}
 static string first(const string& s){return s.substr(0,s.find_first_of(" \t"));}
 void run(const vector<string>& lines,const std::filesystem::path& dir,int depth){
  if(depth>32)fail("macro/include nesting exceeds 32");
  for(size_t i=0;i<lines.size();++i){
   if(++steps>1000000)fail("preprocessing limit exceeded");
   const auto& raw=lines[i];string s=trim(raw.substr(0,outside(raw,'#'))), op=first(s), tail=trim(s.substr(op.size()));
   if(op==".include"){
    auto path=dir/decode_literal(tail,'"');ifstream f(path);if(!f)fail("cannot open include: "+path.string());
    vector<string> src;string x;while(getline(f,x))src.push_back(x);if(f.bad())fail("include read failed: "+path.string());run(src,path.parent_path(),depth+1);continue;
   }
   if(op==".macro"){
    string key=tail.substr(0,tail.find_first_of(" \t,"));if(!name(key)||macros.count(key))fail("invalid or duplicate macro: "+key);
    string ps=tail.substr(key.size());replace(ps.begin(),ps.end(),',',' ');istringstream args(ps);Macro m;string arg;
    while(args>>arg){if(!name(arg)||find(m.params.begin(),m.params.end(),arg)!=m.params.end())fail("invalid macro parameter: "+arg);m.params.push_back(arg);}
    for(++i;i<lines.size();++i){auto q=first(trim(lines[i].substr(0,outside(lines[i],'#'))));if(q==".endm")break;if(q==".macro")fail("nested macro definition not supported");m.body.push_back(lines[i]);}
    if(i==lines.size())fail("missing .endm: "+key);
    macros.emplace(key,move(m));continue;
   }
   if(op==".endm")fail("unexpected .endm");
   auto colon=outside(s,':');string label;
   if(colon!=string::npos){label=s.substr(0,colon+1);s=trim(s.substr(colon+1));op=first(s);tail=trim(s.substr(op.size()));}
   auto it=macros.find(op);if(it==macros.end()){out.push_back(raw);continue;}
   auto mac=it->second;vector<string> args;
   while(!tail.empty()){auto p=outside(tail,',');auto a=trim(tail.substr(0,p));if(a.empty())fail("empty macro argument");args.push_back(a);if(p==string::npos)break;tail=trim(tail.substr(p+1));if(tail.empty())fail("missing macro argument");}
   if(args.size()!=mac.params.size())fail("wrong number of macro arguments: "+op);
   if(!label.empty())out.push_back(label);
   auto uid=to_string(serial++);
   for(auto& line:mac.body){string x;for(size_t p=0;p<line.size();){if(line[p]!='\\'||p+1==line.size()){x+=line[p++];continue;}
    if(line[p+1]=='@'){x+=uid;p+=2;continue;}if(line.compare(p,3,"\\()") ==0){p+=3;continue;}
    size_t end=p+1;while(end<line.size()&&id(line[end]))++end;
    auto param=find(mac.params.begin(),mac.params.end(),line.substr(p+1,end-p-1));if(param==mac.params.end())x+=line[p++];else{x+=args[param-mac.params.begin()];p=end;}}
    line=move(x);}
   run(mac.body,dir,depth+1);
  }
 }
};
void local_labels(vector<string>& src){
 map<string,vector<size_t>> defs;
 auto digits=[](const string& s){return !s.empty()&&all_of(s.begin(),s.end(),[](unsigned char c){return isdigit(c);});};
 auto mangle=[](const string& n,size_t i){return ".__rvlocal_"+n+"_"+to_string(i);};
 for(size_t i=0;i<src.size();++i){auto& s=src[i];s=s.substr(0,outside(s,'#'));auto p=outside(s,':');if(p==string::npos)continue;auto n=trim(s.substr(0,p));if(digits(n)){defs[n].push_back(i);s=mangle(n,i)+s.substr(p);}}
 for(size_t i=0;i<src.size();++i){string x;const auto& s=src[i];char q=0;
  for(size_t p=0;p<s.size();){char c=s[p];if(q){x+=c;++p;if(c=='\\'&&p<s.size())x+=s[p++];else if(c==q)q=0;continue;}if(c=='\''||c=='"'){q=c;x+=c;++p;continue;}
   if(Preprocessor::id(c)){size_t e=p+1;while(e<s.size()&&Preprocessor::id(s[e]))++e;auto tok=s.substr(p,e-p),n=tok.substr(0,tok.size()-1);if(digits(n)&&(tok.back()=='f'||tok.back()=='b')){const auto& v=defs[n];auto j=upper_bound(v.begin(),v.end(),i);if(tok.back()=='b'){if(j==v.begin())fail("unresolved local label: "+tok);--j;}else if(j==v.end())fail("unresolved local label: "+tok);x+=mangle(n,*j);}else x+=tok;p=e;}else{x+=c;++p;}}
  src[i]=move(x);
 }
}

int main(int argc,char** argv){int row=0;try{
 if(argc<2||argc>3){cerr<<"usage: rv32asm input.s [output.bin]\n";return 1;}
 namespace fs=std::filesystem;fs::path input=argv[1],bin=input;if(argc==3)bin=argv[2];else bin.replace_extension(".bin");fs::path lst=bin;lst.replace_extension(".lst");
 auto same=[](const fs::path& a,const fs::path& b){return fs::weakly_canonical(a)==fs::weakly_canonical(b)||(fs::exists(a)&&fs::exists(b)&&fs::equivalent(a,b));};
 if(same(bin,input)||same(lst,input)||same(bin,lst))fail("input and output paths must be different");
 ifstream in(input);if(!in)fail("cannot open input");vector<Line> lines;vector<string> source;string raw;while(getline(in,raw))source.push_back(raw);if(in.bad())fail("input read failed");Preprocessor prep;prep.run(source,input.parent_path(),0);auto expanded=prep.out;local_labels(expanded);for(size_t i=0;i<expanded.size();++i){++row;auto l=parse(row,expanded[i]);l.raw=prep.out[i];lines.push_back(move(l));}
 Symbols constants={{"TEXT_START",{START,'T'}},{"_stack_top",{STACK,'='}}};set<string> defined={"TEXT_START","_stack_top","_data_start","_bss_start","_bss_end"},globals;auto declare=[&](const string& s){if(!name(s))fail("invalid symbol name: "+s);if(!defined.insert(s).second)fail("duplicate symbol: "+s);};
 for(auto& l:lines){row=l.no;if(!l.label.empty())declare(l.label);if(l.op==".string")l.op=".asciz";if(l.op==".p2align")l.op=".align";if(l.op==".set")l.op=".equ";
 if(l.op==".section"){count(l,1);l.op=l.a[0];l.a.clear();if(l.op!=".text"&&l.op!=".data"&&l.op!=".bss"&&l.op!=".rodata")fail("unsupported section: "+l.op);}
 if(l.op==".rodata")l.op=".data";
 if(l.op==".equ"){count(l,2);declare(l.a[0]);constants.emplace(l.a[0],Sym{value(l.a[1],constants),'='});}else if(l.op==".globl"||l.op==".global"){count(l,1);if(!name(l.a[0]))fail("invalid global name");globals.insert(l.a[0]);}else if(l.op=="li"){count(l,2);l.size=8;}}
 // Layout phase: repeat only if a symbolic li changes size. Section starts
 // depend on the preceding section, so align using actual addresses.
 Symbols sy;array<N,3> bases{},ends{};set<vector<N>> visited;
 for(;;){vector<N> state;for(const auto& l:lines)if(l.op=="li")state.push_back(l.size);if(!visited.insert(state).second)fail("li sizes do not converge; use explicit lui/addi");sy=constants;int sec=0;
 for(auto& l:lines){row=l.no;if(l.op==".text"||l.op==".data"||l.op==".bss"){count(l,0);if(!l.label.empty())fail("label cannot prefix a section switch");sec=l.op==".text"?0:l.op==".data"?1:2;}l.sec=sec;}
 for(int s=0;s<3;++s){N pc=bases[s]=s==0?START:align_up(ends[s-1],16);for(auto& l:lines){if(l.sec!=s)continue;row=l.no;l.pc=pc;if(!l.label.empty())sy.emplace(l.label,Sym{pc,"TDB"[s]});const string& o=l.op;N n=0;
 if(o.empty()||o==".equ"||o==".globl"||o==".global"||o==".text"||o==".data"||o==".bss"){}
 else if(o==".space"||o==".align"||o==".balign"||o==".org"){count(l,1);N k=value(l.a[0],constants);if(o==".org"){N dest=bases[s]+check(k,0,LIMIT,"section offset");if(dest<pc)fail(".org cannot move backward");n=dest-pc;}else if(o==".balign"){check(k,1,LIMIT,"byte alignment");n=(k-pc%k)%k;}else n=o==".space"?check(k,0,LIMIT,"space size"):align_up(pc,N(1)<<check(k,0,26,"alignment exponent"))-pc;}
 else if(s==2)fail("only .space and .align may allocate in .bss");
 else if(int w=width(o)){if(l.a.empty())fail("missing data operands");n=N(w)*l.a.size();}
 else if(o==".ascii"||o==".asciz")n=strings(l).size();
 else if(o.front()=='.')fail("unsupported directive: "+o);
 else{if(s!=0)fail("instruction must be in .text");n=o=="li"?l.size:o=="la"?8:4;}
 l.size=n;pc+=n;if(pc>LIMIT)fail("section exceeds board memory");}ends[s]=pc;}
 sy["_data_start"]={bases[1],'D'};sy["_bss_start"]={bases[2],'B'};sy["_bss_end"]={ends[2],'B'};
 bool change=false;for(auto& l:lines)if(l.op=="li"){row=l.no;N n=small(value(l.a[1],sy))?4:8;if(n!=l.size){l.size=n;change=true;}}if(!change)break;
 }
 // Encoding phase: validate everything before opening output files.
 vector<unsigned char> image((ends[1]>bases[1]?ends[1]:ends[0])-START,0);
 struct Entry{N pc; uint64_t word; int bytes; string raw;};vector<Entry> entries;
 auto emit=[&](N pc,uint64_t x,int w,const string& src){for(int i=0;i<w;++i)image.at(pc-START+i)=static_cast<unsigned char>(x>>(8*i));entries.push_back({pc,x,w,src});};
 for(const auto& l:lines){row=l.no;const auto& o=l.op;if(l.sec==2||o.empty())continue;N pc=l.pc;string src=l.raw;
 if(int w=width(o)){
 if(w==2&&pc%2)cerr<<input.string()<<':'<<row<<": warning: unaligned .half\n";
 for(const auto& a:l.a){uint64_t bits=0;
  if(o==".float"||o==".double"){
   static_assert(sizeof(float)==4&&sizeof(double)==8&&numeric_limits<float>::is_iec559&&numeric_limits<double>::is_iec559,"IEEE-754 required");
   size_t end=0;try{if(w==4){float f=stof(a,&end);U u;memcpy(&u,&f,4);bits=u;}else{double d=stod(a,&end);memcpy(&bits,&d,8);}}catch(const exception&){fail("invalid floating literal: "+a);}if(end!=a.size())fail("invalid floating literal: "+a);
  }else if(w==8){
   size_t p=(!a.empty()&&(a[0]=='+'||a[0]=='-'))?1:0, start=p;int base=10;
   if(a.compare(p,2,"0x")==0||a.compare(p,2,"0X")==0){base=16;p+=2;}else if(a.compare(p,2,"0b")==0||a.compare(p,2,"0B")==0){base=2;p+=2;}
   auto digit=[](char c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:99;};
   if(p<a.size()&&all_of(a.begin()+p,a.end(),[&](char c){return digit(c)<base;})&&(base!=10||isdigit((unsigned char)a[start]))){for(;p<a.size();++p){unsigned d=digit(a[p]);if(bits>(UINT64_MAX-d)/base)fail(".dword literal exceeds 64 bits: "+a);bits=bits*base+d;}if(a[0]=='-'){if(bits>(uint64_t(1)<<63))fail(".dword signed literal out of range: "+a);bits=0-bits;}}
   else bits=uint64_t(value(a,sy));
  }else{N top=w==4?0xffffffffLL:(N(1)<<(8*w))-1;N bot=-(N(1)<<(8*w-1));bits=check(value(a,sy),bot,top,o);}
  emit(pc,bits,w,src);pc+=w;src.clear();}
 }
 else if(o==".ascii"||o==".asciz"){for(unsigned char b:strings(l)){emit(pc++,b,1,src);src.clear();}}
 else if(o.front()!='.'){if(pc%4)fail("instruction address is not 4-byte aligned");auto words=encode(l,sy);if(N(words.size())*4!=l.size)fail("internal layout mismatch");for(U w:words){emit(pc,w,4,src);pc+=4;src.clear();}}
 }
 stable_sort(entries.begin(),entries.end(),[](const Entry& a,const Entry& b){return a.pc<b.pc;});row=0;
 ofstream list(lst);if(!list)fail("cannot create listing");list<<hex<<uppercase<<setfill('0');for(const auto& e:entries){uint64_t mask=e.bytes==8?UINT64_MAX:(uint64_t(1)<<(8*e.bytes))-1;list<<setw(8)<<e.pc<<"  "<<setw(e.bytes==8?16:8)<<(e.word&mask)<<"  "<<e.raw<<'\n';}list<<"\nSYMBOLS\n";for(const auto& kv:sy)list<<kv.first<<"  "<<setw(8)<<U(kv.second.value)<<"  "<<kv.second.type<<(globals.count(kv.first)?" G":"")<<'\n';list.close();if(!list)fail("listing write failed");
 ofstream out(bin,ios::binary);if(!out)fail("cannot create binary");if(!image.empty())out.write(reinterpret_cast<const char*>(image.data()),image.size());out.close();if(!out){error_code ec;fs::remove(bin,ec);fail("binary write failed");}return 0;
 }catch(const exception& e){if(argc>1)cerr<<argv[1];if(row)cerr<<':'<<row;cerr<<": error: "<<e.what()<<'\n';return 1;}}
