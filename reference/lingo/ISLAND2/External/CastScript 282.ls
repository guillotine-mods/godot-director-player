on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, dubi
  if whereami = label("hall1") then
    yyy = "allright"
    if dubi < 2 then
      yyy = "notallright"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "glass") and (yyy = "notallright") then
          yyy = "allright"
        end if
      end repeat
    end if
    if yyy = "allright" then
      ifmovie = "1,toware"
      y = 188
      x = 283
      y2 = 308
      x2 = 238
      egozv = y
      egozh = x
      put x2 into item 2 of nextroomdata
      put y2 into item 3 of nextroomdata
      put "warehouse1" into item 1 of nextroomdata
      walkonby2()
    end if
  end if
end
