#define TOK_NUM 0x100
#define TOK_NAME 0x101
#define TOK_STR 0x102
#define TOK_CHR 0x103
#define LEXf_USE_LAST_CHAR 1
#define LEXF_CMD_LINE 4
#define LEXF_WANTS_INPUT 8
#define LEXF_SILENT 16
class CLexer {
  U8 filename[STR_LEN],str[STR_LEN];
  U8 *body;
  I32 flags,last_chr;
  I64 col,ln,pos,tok,chr;
  F64 num;
};
CLexer *LexerNew(U8 *buf,U8 *filename=NULL) {
  CLexer *l=CAlloc(sizeof CLexer);
  l->ln=1;
  l->col=1;
  if(filename)
    StrCpy(l->filename,filename);
  l->body=StrNew(buf);
  return l;
}
U0 LexerDel(CLexer *l) {
  Free(l->body);
  Free(l);
}
U8 LexGetChar(CLexer *l) {
  U8 ret;
again:
  if(Btr(&l->flags,LEXf_USE_LAST_CHAR)) {
    return l->last_chr;
  }
  if(l->flags&LEXF_WANTS_INPUT) {
    l->flags&=~LEXF_WANTS_INPUT;
    l->body=GetStr(">>> ");
    l->pos=0;
    goto again;
  }
  ret=l->body[l->pos++];
  if(ret=='\n') l->ln++,l->col=1;
  l->last_chr=ret;
  if(!l->last_chr&&(l->flags&LEXF_CMD_LINE)) {
    l->flags|=LEXF_WANTS_INPUT;
  }
  return l->last_chr;
}
I64 LexInt(CLexer *l,I64 radix=10) {
  I64 r=0,ch,digit;
  while(ch=LexGetChar(l)) {
    ch=ToUpper(ch);
    if('0'<=ch<='9') {
      digit=ch-'0';
    } else if('A'<=ch<='Z') {
      digit=ch-'A'+10;
    } else
      break;
    if(digit>=radix)
      break;
    r*=radix;
    r+=digit;
  }
  Bts(&l->flags,LEXf_USE_LAST_CHAR);
  return r;
}
U0 LexExcept(CLexer *l,U8 *fmt,...) {
  if(!(l->flags&LEXF_SILENT)) {
    fmt=StrPrintJoin(NULL,fmt,argc,argv);
    "(%s:%d,%d)  %s\n",l->filename,l->ln,l->pos,fmt;
    Free(fmt);
  }
  throw('Shlong');
}
U0 LexWarn(CLexer *l,U8 *fmt,...) {
  if(!(l->flags&LEXF_SILENT)) {
    fmt=StrPrintJoin(NULL,fmt,argc,argv);
    "(%s:%d,%d)  %s\n",l->filename,l->ln,l->pos,fmt;
    Free(fmt);
  }
}
I64 IsOperatorChr(I64 ch) {
  switch(ch) {
    case '+':
    case '-':
    case '*':
    case '/':
    case '&':
    case '=':
    case '>':
    case '<':
    case '~':
    case '!':
    case ',':
    case '\\':
      return TRUE;
  }
  return FALSE;
}
I64 Lex(CLexer *l) {
  I64 radix=10;
  I64 idx;
  F64 num=0,frac=0,mul=1.;
again:;
  U8 ch=LexGetChar(l);
  if(Bt(char_bmp_white_space,ch))
   goto again;
  if(Bt(char_bmp_dec_numeric,ch)) {
    Bts(&l->flags,LEXf_USE_LAST_CHAR);
    //Radix?
n:
    radix=LexInt(l);
    ch=LexGetChar(l);
    if(ch=='R'||ch=='r') {
      num=LexInt(l);
    } else if(ch=='.') {
     num=radix;
dot:
      frac=LexInt(l);
      if(frac)
        num+=frac*Pow10(-Floor(1+Log10(frac)));
exp:
      ch=LexGetChar(l);
      if(ch=='e'||ch=='E') {
	num*=Pow10(LexInt(l));
      } else
	Bts(&l->flags,LEXf_USE_LAST_CHAR);
    } else {
      num=radix;
      Bts(&l->flags,LEXf_USE_LAST_CHAR);
      goto exp;
    }
    l->num=num*mul;
    return l->tok=TOK_NUM;
  } else if(ch=='\'') {
    idx=0;
    do {
      ch=LexGetChar(l);
      if(ch=='\'') break;
      if(idx+1>=STR_LEN)
        LexExcept(l,"String is too big");
      l->str[idx++]=ch;
    } while(TRUE);
    l->str[idx]=0;
    return l->tok=TOK_STR;
  } else if(IsOperatorChr(ch)) {
    idx=0;
    l->tok=0;
    if(ch=='-') {
      l->tok.u8[idx++]=ch;
      ch=LexGetChar(l);
      Bts(&l->flags,LEXf_USE_LAST_CHAR);
      if(Bt(char_bmp_dec_numeric,ch)) {
	mul=-1.;
	goto n;
      }
    }
    Bts(&l->flags,LEXf_USE_LAST_CHAR);
    do {
      ch=LexGetChar(l);
      if(!IsOperatorChr(ch)) break;
      if(idx+1>=8)
        LexExcept(l,"Invalid operator '%c'");
      l->tok.u8[idx++]=ch;
    } while(TRUE);
    Bts(&l->flags,LEXf_USE_LAST_CHAR);
    return l->tok;
  } else if(ch=='$$') {
    l->chr=LexGetChar(l);
    return l->tok=TOK_CHR;
  }
  switch(ch) {
    case '[':
    case ']':
    case '(':
    case ')':
    case ':':
    case '_':
    case '|':
    case ';':
    case '^':
    case '#':
    case 0:
    return l->tok=ch;
    case '.':
    if(Bt(char_bmp_dec_numeric,LexGetChar(l))) {
      Bts(&l->flags,LEXf_USE_LAST_CHAR);
      goto dot;
    }
    Bts(&l->flags,LEXf_USE_LAST_CHAR);
    return l->tok='.';
  }
  if(Bt(char_bmp_alpha_numeric,ch)) {
    idx=0;
    Bts(&l->flags,LEXf_USE_LAST_CHAR);
    do {
      ch=LexGetChar(l);
      if(!Bt(char_bmp_alpha_numeric,ch)) break;
      if(idx+1>=STR_LEN)
        LexExcept(l,"Name is too big");
      l->str[idx++]=ch;
    } while(TRUE);
    l->str[idx]=0;
    Bts(&l->flags,LEXf_USE_LAST_CHAR);
    return l->tok=TOK_NAME;
  }
  LexExcept(l,"Unexpected character '%d'.",ch);
}
/*U8 *test="example_With_Number: x"
"    | y |"
"    true & false not & (nil isNil) ifFalse: [self halt]."
"    y := self size + super size."
"    #($$a #a 'a' 1 1.0 .1 .1e10)"
"        do: [ :each |"
"            Transcript show: (each class name);"
"                       show: ' ']."
"    ^x < y";
CLexer *l=LexerNew(test);
while(Lex(l)) {
  switch(l->tok) {
    case TOK_CHR:
      "CHR:%c\n",l->chr;
      break;
    case TOK_NAME:
      "NAME:%s\n",l->str;
      break;
    case TOK_STR:
      "STR:%s\n",l->str;
      break;
    case TOK_NUM:
      "NUM:%n\n",l->num;
      break;
    default:
      "%c\n",l->tok;
      break;
  }
}
*/