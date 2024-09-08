//Compile non-numbers first
DumpAst(ast);
        for(idx=0;idx<cnt+1;idx++) { //+1 includes self
	  if(!IsF64ExprNode(locals,cur)) {
	    has_non_f64|=ToBool(StrCmp(cur->var_class_name,"CFrogNum"));
"fsdf\n";
DumpAst(ast);
"%s\n",cur->var_class_name;
	  }
	  cur=cur->next;
        }
///Compile F64 after the label prolog
        cur=ast->args.next;
        if(!has_non_f64) {
DumpAst(ast);
Beep;
//Replace the (object) CFrogNum's with F AST_STACK_TEMPORARY
          cur=ast->args.next;
	  for(idx=0;idx<cnt+1;idx++) { //+1 includes self
	    if(!IsF64ExprNode(locals,cur)) { //All of them have CFrogNum(See above)
	      cur->type=AST_STACK_TEMPORARY;
	      cur->stk_idx=stack_depth+idx;
	    }
	    cur=cur->next;
	  }
	  DocPrint(doc,"%s=FrogNumNew(",StackFrame2Var(stack_depth));
	  add_paren=TRUE;
	  goto force_f64;
        }
