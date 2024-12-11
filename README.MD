# Poopin Frogs
 This README.MD is under development,stay tuned

# Making images/textures for FrogsEngine
Run `TextureEditor.HC`.

[Editing a Texture in FrogsEngine](https://aiwnios.com/ViewVideo.HC?view=FrogsEngine/EditTexture.DD)

## Texture editor controls
 - File
   - `Ctrl+O` For opening a file
   - `Ctrl+A` For save as
   - `Ctrl+Z` Undo
 - Tools
   - `p` Paint
   - `c` Select Color
   - `l` Line
   - `Shift+P` PolyLine
   - `t` Set Thickness
   - `Shift+B` Set Bounds(Resize image)
   - `E` Ellipse
   - `Ctrl+C` Copy
   - `Ctrl+X` Cut
   - `Ctrl+V` Paste
 - Animation
   - `f` Select Frame
   - `d` delete current frame
   - `s` Set Animation speed

# Writing SmallTalk80-like(PoopTalk) Code.
  
  FrogsEngine uses a SmallTalk-80 like langauge(See `SmallTalk/Interpreter.HC`).
  
  The source code for the SmallTalk stuff should be easy enough to understand.
  
  Pooptalk is strongly typed sort of. You can assign types like this:

  ```
  someMethod: x* ->CFrogNum
  |
    local=CFrogStr
  |
    '-> means return type(above)'.
    '* means any type'.
    
    local _ 'abc' .
    ^ x + 2
  ```
  
## Mini PoopTalk Tutorial

  First open the editor in `SmallTalk/Studio.HC`.
  
  You'll get a sexy class editor,exit it(`Shift+Escape`) and type `STRepl;` and I will show you how to use pooptalk
  
### Logging to console(Aiwnios).
  `show` doesnt log to screen,it logs to the console output
  
  So if you type:
  ```
  #(1 2 3) printString show
  ```
  You should see this in the console window
  ```
  '#(1 2 3 )'
  ```
### Here is a Sexy Syntax guide

  ```
  'Comment(Just a string literal)'.
  
  'Symbols act a global vars'.
  
  #global_var _ 'abc' .
  #global_var show . 'Show the value of the global'.
  (#global_var size + 2) show . 'Add 2 to size and show'.

  'Array'.
  #(1 2 3) do:[:x=CFrogNum| x show ].
  'Nested array(needs # unlike regular smalltalk)'.
  #(#(1 2 3) #(4 5 6) #(7 8 9)) printString show.
  
  'Member access' .
  #thing _ C3DThing new.
  #thing->x _ 123 .
  #thing->x show .
  ```
  PoopTalk lets you access class members via `var->member`.

