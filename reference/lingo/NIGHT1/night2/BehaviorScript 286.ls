on exitFrame
  x = "show"
  repeat with i = 1 to 30
    if line i of field "objectsfield" of castLib "master" = "masor" then
      x = "hide"
    end if
  end repeat
  if x = "hide" then
    set the visible of sprite 17 to 0
  else
    set the visible of sprite 17 to 1
  end if
end
