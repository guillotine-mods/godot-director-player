on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, guard
  if guard > 0 then
    if whereami = label("rachup") then
      ifmovie = "1,rachupdown"
      newsyz = 4
      y = 308
      x = 238
      y2 = 309
      x2 = 15
    else
      if whereami = label("fort") then
        ifmovie = "1,climbdownfort"
        newsyz = 4
        y = 404
        x = 188
        y2 = 288
        x2 = 498
      end if
    end if
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "mountain" into item 1 of nextroomdata
    f = "show"
    repeat with i = 1 to 30
      if line i of field "objectsfield" of castLib "master" = "igkey" then
        f = "hide"
      end if
    end repeat
    repeat with i = 1 to 10
      if line i of field "plane" of castLib "master" = "igkey" then
        f = "hide"
      end if
    end repeat
    if f = "hide" then
      sprite(18).visible = 1
    else
      sprite(18).visible = 0
    end if
    walkonby()
  end if
end
