on peoplefunk
  global nextroomdata, ifmovie
  repeat with i = 18 to 21
    puppetSprite(i, 0)
  end repeat
  if item 1 of nextroomdata = "recept" then
    peoplecont(5)
  else
    if item 1 of nextroomdata = "loby" then
      peoplecont(6)
    else
      if item 1 of nextroomdata = "rooma" then
        if item 2 of ifmovie = "torooma" then
          peopleinroom("a")
        end if
      else
        if item 1 of nextroomdata = "roomb" then
          if item 2 of ifmovie = "toroomb" then
            peopleinroom("b")
          end if
        else
          isthere = "no"
        end if
      end if
    end if
  end if
end

on peoplecont i
  global inexits, nextroomdata
  x = value(item i of inexits)
  x = x + 1
  if x > 8 then
    x = 1
  end if
  put x into item i of inexits
  if x > 4 then
    if i = 5 then
      set the visible of sprite 19 to 0
      set the visible of sprite 21 to 1
    else
      if i = 6 then
        set the visible of sprite 18 to 0
        set the visible of sprite 34 to 1
      end if
    end if
  else
    if i = 5 then
      set the visible of sprite 19 to 1
      set the visible of sprite 21 to 0
    else
      if i = 6 then
        set the visible of sprite 18 to 1
        set the visible of sprite 34 to 0
      end if
    end if
  end if
  if (value(item 6 of inexits) = "4") and (item 1 of nextroomdata = "recept") then
    set the visible of sprite 18 to 1
    set the visible of sprite 34 to 0
  end if
end

on peopleinroom whichroom
  set the visible of sprite 18 to 0
  set the visible of sprite 19 to 0
  set the visible of sprite 32 to 0
  set the visible of sprite 35 to 0
  set the visible of sprite 34 to 0
  x = random(5)
  x = x - 1
  if x > 0 then
    i = 1
    repeat while i <= x
      y = random(5)
      case y of
        1:
          set the visible of sprite 18 to 1
        2:
          set the visible of sprite 32 to 1
        3:
          set the visible of sprite 19 to 1
        4:
          set the visible of sprite 35 to 1
        5:
          set the visible of sprite 34 to 1
      end case
      i = i + 1
    end repeat
  end if
end
