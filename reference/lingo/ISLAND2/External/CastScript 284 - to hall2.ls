on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, soundspath
  if sprite(29).visible = 0 then
    if whereami = label("hall1") then
      ifmovie = "0,0"
      y = 300
      x = 20
      y2 = 300
      x2 = 630
    end if
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "hall2" into item 1 of nextroomdata
    walkonby2()
  else
    vcb = 0
    repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
      if line i of field "objectsfield" = "pirats" then
        vcb = 1
      end if
    end repeat
    if vcb = 1 then
      go(1, "divefigt.dxr")
    else
      sound playFile 1, soundspath & "subblock.aif"
    end if
  end if
end
