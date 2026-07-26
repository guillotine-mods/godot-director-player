on exitFrame
  global inexits, usfultalking, usfulline, syz, egozh, egozv
  talkproc("b", "hat-ans", "tennisgo")
  if soundBusy(1) then
    xxx = "a"
    rin = 18
    hezzz = "left"
    who = item usfultalking of line usfulline of field "hat-ans" of castLib "master"
    if who contains "hat" then
      set the memberNum of sprite 30 to the number of member ("stand" & hezzz & syz) of castLib 1
      set the locV of sprite 30 to egozv
      set the locH of sprite 30 to egozh
      set the memberNum of sprite rin to the number of member (xxx & who) of castLib "wonder"
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
      set the memberNum of sprite rin to the number of member (xxx & "hatlop1") of castLib "wonder"
    end if
  end if
end
