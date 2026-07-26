on exitFrame
  global inexits, usfultalking, usfulline, syz, egozh, egozv
  talkproc("f", "ish-ans", "lobygo")
  if soundBusy(1) then
    if value(item 6 of inexits) > 4 then
      xxx = "a"
      rin = 34
      if the locH of sprite 30 > 405 then
        hezzz = "left"
      else
        hezzz = "right"
      end if
    else
      xxx = "b"
      rin = 18
      hezzz = "left"
    end if
    x = the memberNum of sprite 18
    x = member(x, "wonder").name
    if x = "aishspk2" then
      set the locH of sprite rin to the locH of sprite rin + 7
    end if
    who = item usfultalking of line usfulline of field "ish-ans" of castLib "master"
    if who contains "ish" then
      puppetSprite(34, 1)
      set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
      set the locV of sprite 30 to egozv
      set the locH of sprite 30 to egozh
      set the memberNum of sprite rin to the number of member (xxx & who) of castLib "wonder"
      if who = "ishspk2" then
        set the locH of sprite rin to the locH of sprite rin - 7
      end if
    else
      if who contains "mov" then
        puppetSprite(34, 0)
        puppetSprite(18, 0)
        play frame "ishgivemov"
        puppetSprite(18, 1)
        puppetSprite(34, 1)
      else
        if who contains "jos" then
          set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
          set the locV of sprite 30 to egozv
          set the locH of sprite 30 to egozh
          set the memberNum of sprite rin to the number of member (xxx & "ishlop1") of castLib "wonder"
          play frame "lobjos"
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
          set the memberNum of sprite rin to the number of member (xxx & "ishlop1") of castLib "wonder"
        end if
      end if
    end if
  else
    puppetSprite(34, 0)
  end if
end
