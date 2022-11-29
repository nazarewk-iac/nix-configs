import textwrap


def cleanup(text):
    text = text.removeprefix("\n")
    ret = textwrap.dedent(text)
    return ret


complete_unformatted = cleanup("""
2022-10-10
  8:00 - 10:00 #range
  30m #duration
  -30m #duration #negative
  11:00 - ? #range #open
  <23:00 - 01:00 #range #day-shift-backwards
  23:00 - 01:00> #range #day-shift-forwards
  30m #multiline=0
    #multiline=1


2022-10-11
  <23:00 - 01:00> #range #day-shift-both
""")

complete_formatted = cleanup("""
2022-10-10
  08:00  - 10:00  #range
  30m             #duration
  -30m            #duration #negative
  11:00  - ?      #range #open
  <23:00 - 01:00  #range #day-shift-backwards
  23:00  - 01:00> #range #day-shift-forwards
  30m             #multiline=0
                  #multiline=1

2022-10-11
  <23:00 - 01:00> #range #day-shift-both
""")
