on exitFrame
  global soundspath, globalday, inexits, usfultalking, usfulline, syz, egozh, egozv
  fieldname = "clickoncharacter"
  lastmark = "dwarfsgo"
  usfulobject = "bonday" & globalday
  if usfultalking = 1 then
    r = "not"
    i = 1
    repeat while (i < (the number of lines in field fieldname of castLib "master" + 1)) and (r = "not")
      if item 1 of line i of field fieldname = usfulobject then
        r = i
      end if
      i = i + 1
    end repeat
    if r <> "not" then
      usfulline = r
      egozh = the locH of sprite 30
      egozv = the locV of sprite 30
      if item 2 of line usfulline of field fieldname of castLib "master" = "0" then
        sound playFile 1, soundspath & "bonday" & globalday & usfultalking & ".aif"
        put 1 into item 2 of line usfulline of field fieldname of castLib "master"
        usfultalking = usfultalking + 1
      else
        sound playFile 1, soundspath & "bonsay" & random(6) & ".aif"
        usfultalking = 100
      end if
    end if
  else
    if (the number of items in line usfulline of field fieldname of castLib "master" - 2) >= usfultalking then
      sound playFile 1, soundspath & "bonday" & globalday & usfultalking & ".aif"
      usfultalking = usfultalking + 1
    else
      repeat with i = 18 to 21
        puppetSprite(i, 0)
      end repeat
      if member(the memberNum of sprite 30).name contains "right" then
        set the memberNum of sprite 30 to the number of member ("standright" & syz)
      else
        set the memberNum of sprite 30 to the number of member ("standleft" & syz)
      end if
      set the locV of sprite 30 to egozv
      set the locH of sprite 30 to egozh
      go(lastmark)
    end if
  end if
  if soundBusy(1) then
    if the visible of sprite 20 = 1 then
      xxx = "b"
      rin = 20
      hezzz = "right"
    else
      xxx = "a"
      rin = 18
      hezzz = "right"
    end if
    who = item usfultalking + 1 of line usfulline of field "clickoncharacter" of castLib "master"
    if usfultalking = 100 then
      who = "bonspk2"
    end if
    if who contains "bon" then
      set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
      set the locV of sprite 30 to egozv
      set the locH of sprite 30 to egozh
      if who contains "eat" then
        set the visible of sprite rin to 0
        play frame who
        set the visible of sprite rin to 1
      else
        set the memberNum of sprite rin to the number of member (xxx & who) of castLib "wonder"
      end if
    else
      put who
      if who contains "mov" then
        set the visible of sprite rin to 0
        play frame who
        set the visible of sprite rin to 1
      else
        if hezzz = "left" then
          case syz of
            9:
              hezspeaks = "-11,-122"
            8:
              hezspeaks = "-10,-114"
            7:
              hezspeaks = "-9,-105"
            6:
              hezspeaks = "-9,-96"
            5:
              hezspeaks = "-8,-88"
            4:
              hezspeaks = "-7,-79"
          end case
        else
          case syz of
            9:
              hezspeaks = "13,-123"
            8:
              hezspeaks = "12,-114"
            7:
              hezspeaks = "11,-106"
            6:
              hezspeaks = "10,-97"
            5:
              hezspeaks = "9,-88"
            4:
              hezspeaks = "8,-80"
          end case
        end if
        set the locV of sprite 30 to the locV of sprite 30 + value(item 2 of hezspeaks)
        set the locH of sprite 30 to the locH of sprite 30 + value(item 1 of hezspeaks)
        set the memberNum of sprite 30 to the number of member ("h" & syz & hezzz) of castLib 1
        set the memberNum of sprite rin to the number of member (xxx & "bonlop1") of castLib "wonder"
      end if
    end if
  end if
end
