on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, sink, bath, soundspath
  if bath = 1 then
    if whereami = label("bath") then
      ifmovie = "1,bathbath"
      newsyz = 7
      y = 445
      x = 210
      y2 = 284
      x2 = 351
    end if
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "roomb" into item 1 of nextroomdata
    walkonby()
  else
    sound playFile 1, soundspath & "hbath" & random(3) & ".aif"
  end if
end
