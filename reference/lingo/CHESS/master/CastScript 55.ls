on mouseUp
  global soundspath
  set the visible of sprite 22 to 1
  put the text of field "boardinit" into field "board"
  put "H" into item 5 of line 2 of field "board"
  repeat with i = 7 to 9
    set the visible of sprite i to 1
  end repeat
  sound playFile 1, soundspath & "istrt.aif"
  go(marker(1))
end
