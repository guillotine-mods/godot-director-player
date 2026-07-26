on peoplefunk
  global nextroomdata, meetings, globalday, ifmovie
  if (item 1 of nextroomdata = "loby") and (item 4 of meetings <> "done") and (globalday = 1) then
    go(1, "ishday1.dxr")
  else
    if (item 1 of nextroomdata = "rooma") and (item 7 of meetings <> "done") and (item 6 of meetings = "done") and (globalday = 1) then
      go(1, "allin.dxr")
    else
      if (item 1 of nextroomdata = "recept") and (item 6 of meetings <> "done") and (item 5 of meetings = "done") and (globalday = 1) then
        go(1, "tofircpt.dxr")
      else
        if (item 1 of nextroomdata = "recept") and (item 8 of meetings <> "done") and (item 7 of meetings = "done") and (globalday = 1) then
          finishday(1)
        else
          if (item 1 of nextroomdata = "recept") and (item 1 of meetings <> "done") and (globalday = 2) then
            go(1, "morn2.dxr")
          else
            if (item 1 of nextroomdata = "loby") and (item 4 of meetings <> "done") and (globalday = 2) and (item 2 of meetings = "done") and (item 3 of meetings = "done") then
              go(1, "dtcday2.dxr")
            else
              if (item 1 of nextroomdata = "prosdor") and (item 5 of meetings <> "done") and (item 4 of meetings = "done") and (globalday = 2) then
                go(1, "investig.dxr")
              else
                if (item 1 of nextroomdata = "loby") and (item 7 of meetings <> "done") and (item 5 of meetings = "done") and (globalday = 2) then
                  finishday(2)
                else
                  if (item 1 of nextroomdata = "recept") and (item 1 of meetings <> "done") and (globalday = 3) then
                    go(1, "morn3.dxr")
                  else
                    if (item 1 of nextroomdata = "loby") and (item 5 of meetings <> "done") and (item 3 of meetings = "done") and (item 4 of meetings = "done") and (globalday = 3) then
                      finishday(3)
                    end if
                  end if
                end if
              end if
            end if
          end if
        end if
      end if
    end if
  end if
  repeat with i = 18 to 21
    puppetSprite(i, 0)
  end repeat
  if the movieName contains "hotel1" then
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
  end if
end

on peoplecont i
  global sodom, inexits, nextroomdata
  x = value(item i of inexits)
  if sodom = "ok" then
    x = x + 1
  else
    sodom = "ok"
  end if
  if x > 8 then
    x = 1
  end if
  put x into item i of inexits
  if x > 4 then
    if i = 5 then
      sprite(19).visible = 0
      sprite(21).visible = 1
    else
      if i = 6 then
        sprite(18).visible = 0
        sprite(34).visible = 1
      end if
    end if
  else
    if i = 5 then
      sprite(19).visible = 1
      sprite(21).visible = 0
    else
      if i = 6 then
        sprite(18).visible = 1
        sprite(34).visible = 0
      end if
    end if
  end if
  if (value(item 6 of inexits) = "4") and (item 1 of nextroomdata = "recept") then
    sprite(18).visible = 1
    sprite(34).visible = 0
  end if
end

on peopleinroom whichroom
  sprite(18).visible = 0
  sprite(19).visible = 0
  sprite(32).visible = 0
  sprite(35).visible = 0
  sprite(34).visible = 0
  x = random(5)
  x = x - 1
  if x > 0 then
    i = 1
    repeat while i <= x
      y = random(5)
      case y of
        1:
          sprite(18).visible = 1
        2:
          sprite(32).visible = 1
        3:
          sprite(19).visible = 1
        4:
          sprite(35).visible = 1
        5:
          sprite(34).visible = 1
      end case
      i = i + 1
    end repeat
  end if
end
