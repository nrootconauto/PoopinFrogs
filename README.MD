
# Poopin Frogs
 This README.MD is under development,stay tuned

# Editing the World.

  The world is finite in size,I will add a menu in the  future to change its size

  You can place blocks and things in the world(**YOU MIGHT WANT TO PRESS `I` TO TURN INVISIBLE SO ENEMIES DONT ATTACK YOU**).
  
  Its like classic minecaft but with poop.
   
## Things edit menu(Press `t`).
![Thing Edit Shell](ThingEdit1.png)

  From here you can make new things(`Green button`).
  
  You can edit things. **USE  '/' IN THE THING NAMES TO MAKE "states" FOR THE THINGS**
  You get edit the graphics from the things menu.

![Thing Edit Shell](ThingEdit2.png)

## Doors Edit Menu(Press `Shift+d`)


  Doors do what you think they do. They have various properties. Doors will open if you walk into them unless they need a key or have a tag number that isnt 0.

 ### Door Properties
  - Tag Number
	  - When all enemies of a certian tag die,then the door opens.
 - Small Key
	 - Will open if you have a small key
- Big Key
	 - Will open if you have a big key
- Height
	- How tall the door is
	- 
## Block Edit Shell(Press `b`)

![Block Edit Shell](BlockEdit1.png)

This will open a grid,press an item on the grid to edit the block's textures.

Current properties are hard coded. Ask nrootconauto to easily change this(so you can make lights and liquid blocks).

![Block Edit Shell](BlockEdit2.png)

## Poopidex(Press `p`). 
![Poopidex](Poopidex.png)
This is a "dictionary" of stuff. You probably wont need this for now.

## Magic Wand(Select from inventory).
![Select wand](Wand.png)
Select the wand,then use it on a thing(click the thing)

![Use Wand](Wand2.png)
This will let you these properties on a thing
- Tag Number
- Quest	
- And dropped item(when killed). 

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

