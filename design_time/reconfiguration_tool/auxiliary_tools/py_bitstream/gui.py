#!/usr/bin/env python2
# -*- coding: utf-8 -*-
# http://www.pythonware.com/library/Tkinter/introduction/

"""
Using Tk because it seems to be the de facto standard for Python
and seems to be implemented in all Python distributions
(although I had to install python-tk in Ubuntu)
"""



import Tkinter       # All Tk basic widgets
import tkFileDialog  # Open/Save dialogs
import tkMessageBox  # Warnings, errors, infos
from tools.bitstream import Bitstream



bitstr = None



def program_help():
    "Show a (now useless) help box"
    tkMessageBox.showinfo("Help",
            "This should display some help for this GUI.\n"
            "Unfortunately, the author was too lazy to write a proper help.\n"
            "For usage questions, ask Mora directly.")



def launch_open_dialog():
    "Ask for a .bit file to open with a Browse dialog"
    global bitstr
    fname = tkFileDialog.askopenfilename(
            filetypes=[("Bitstreams", "*.bit"), ("All files", "*")])
    if not fname: return
    open_bitstr(fname)

def open_bitstr(fname):
    "Load a .bit file"
    import fpgas  # for fpgas.unknown
    global bitstr
    try:
        bs = Bitstream(fname)
    except Exception as e:
        tkMessageBox.showerror("Error opening `%s'" % fname,
                "The file `%s' could not be opened.\n%s" % (fname, e))
        raise
        return
    bitstr = bs
    if bitstr.fpga == fpgas.unknown:
        tkMessageBox.showwarning("Unknown FPGA model",
                "FPGA model unknown.  This is probably because the FPGA model "
                "wasn't recognized.  You can still see the instructions "
                "by manually setting the FPGA model to a generic one "
                "(e.g. virtex5) with the `Set FPGA model' button, "
                "but you won't be able to extract partial bitstreams.")
    elif bitstr.config_offset is None:
        tkMessageBox.showwarning("Configuration data not found",
                "Unable to find configuration data in bitstream.  "
                "Therefore, it will not be possible to extract "
                "a partial bitstream from this file.")
    bsinfo_fname_stringvar.set(fname)
    update_fpga_info()

def update_fpga_info():
    "Replace the info in the 'FPGA info' box with the info from the loaded BS"
    global bitstr, extract_button, bsinfo_stringvar
    text = bitstr.info(as_string=True)
    bsinfo_stringvar.set(text)
    if bitstr.config_offset is None:
        extract_button.configure(state='disabled')
    else:
        extract_button.configure(state='normal')

def set_bitstr_fpga():
    """
    Manually set the FPGA model from a file if it wasn't set correctly.

    The FPGA model MUST be in the fpgas/ directory.
    """
    import os.path  # extract dir, filename, file ext
    import fpgas  # just to get its path

    global bitstr
    fpgas_dir = os.path.dirname(fpgas.__file__)
    fname = tkFileDialog.askopenfilename(filetypes=[("Bitstreams", "*.py")],
            initialdir=fpgas_dir)
    if not fname: return
    if os.path.realpath(os.path.dirname(fname)) != os.path.realpath(fpgas_dir):
        tkMessageBox.showerror("Invalid path",
                "Model file must be in `fpgas' directory")
        return
    fpganame = os.path.splitext(os.path.basename(fname))[0]
    bitstr.set_fpga(fpganame)
    update_fpga_info()

def bitstr_dump():
    "Disassemble the bitstream instructions and display them"
    global bitstr
    if not bitstr.fpga.dump:
        tkMessageBox.showwarning("Unknown FPGA model",
                "FPGA model isn't set.  This is probably because the FPGA model "
                "wasn't recognized.  You can still see the instructions "
                "by manually setting the FPGA model to a generic one "
                "(e.g. virtex5) with the `Set FPGA model' button.")
        set_fpga_model_button.flash()
        return
    text = bitstr.dump(as_string=True)

    def save_dump():
        dump_file = tkFileDialog.asksaveasfile(mode="w",
                filetypes=[("Text files", "*.txt"), ("All files", "*")])
        if not dump_file: return
        dump_file.write(text)
        dump_file.close()

    new_window = Tkinter.Toplevel()
    buttons = Tkinter.Frame(new_window)
    buttons.pack(side='bottom')
    Tkinter.Button(buttons, text="Export as text file", command=save_dump).pack(side='left')
    Tkinter.Button(buttons, text="Close", command=new_window.destroy).pack(side='left')
    Tkinter.Label(new_window, text=text, justify='left', font="TkFixedFont").pack(side='bottom')

    if len(text) > 10000:
        tkMessageBox.showwarning("Instruction list too long",
                "The bitstream might be too long to be displayed correctly.  "
                "Consider exporting it to a file.")



def all_rows():
    "Set Y0 and Yf spinboxes to the limit values"
    box_Y0.delete(0, 'end')
    box_Yf.delete(0, 'end')

def all_cols():
    "Set X0 and Xf spinboxes to the limit values"
    box_X0.delete(0, 'end')
    box_Xf.delete(0, 'end')

def all_word():
    "Set W0 and Wf spinboxes to the limit values"
    box_W0.delete(0, 'end')
    box_Wf.delete(0, 'end')

def all_frms():
    "Set F0 and Ff spinboxes to the limit values"
    box_F0.delete(0, 'end')
    box_Ff.delete(0, 'end')



def extract_pbs():
    "Extract PBS and save it to a file"
    import os.path  # extract dir, filename, file extension

    Y0 = box_Y0.get()
    Yf = box_Yf.get()
    X0 = box_X0.get()
    Xf = box_Xf.get()
    W0 = box_W0.get()
    Wf = box_Wf.get()
    F0 = box_F0.get()
    Ff = box_Ff.get()

    Y0 = int(Y0)   if Y0 else None  # if blank, set to None (start/end),
    Yf = int(Yf)+1 if Yf else None  # else, to value converted to number
    X0 = int(X0)   if X0 else None
    Xf = int(Xf)+1 if Xf else None
    W0 = int(W0)   if W0 else None
    Wf = int(Wf)+1 if Wf else None
    F0 = int(F0)   if F0 else None
    Ff = int(Ff)+1 if Ff else None

    filetype = Tkinter.StringVar()
    pbs_file = tkFileDialog.asksaveasfile(mode="wb",
            filetypes=[("Partial bitstream", "*.pbs"),
                    ("Byte-reversed partial bitstream", "*.rpb")],
            typevariable=filetype)
    if not pbs_file: return

    chunk = bitstr[Y0:Yf, X0:Xf, W0:Wf, F0:Ff]
    #filetype might be "Description (*.ext)" (Linux) or "Description" (Windows)
    if "Byte-reversed partial bitstream" in filetype.get():
        w = bitstr.fpga.word
        for i in xrange(w//2):  # swap each i'th bytes (if w=4, then {i=0;i=1})
            chunk[i::w], chunk[w-1-i::w] = chunk[w-1-i::w], chunk[i::w]

    pbs_file.write(chunk)
    pbs_file.close()






##################
## TK INTERFACE ##
##################



window = Tkinter.Tk()
window_main_frame = Tkinter.Frame(window, padx=5, pady=5)
window_main_frame.pack(fill='both', expand=1)

window_bs   = Tkinter.Frame(window_main_frame)
window_pbs  = Tkinter.Frame(window_main_frame)
window_quit = Tkinter.Frame(window_main_frame)

window_quit.pack(side='bottom', fill='x')
window_bs  .pack(side='top',    fill='both', expand=1)
window_pbs .pack(side='top',    fill='x')



## Bitstream action buttons ##

bsinfo_fname_stringvar = Tkinter.StringVar(value="No file open")
bsinfo_fname = Tkinter.Label(window_bs, font="TkDefaultFont -12 bold",
        textvariable=bsinfo_fname_stringvar, justify='left', anchor='nw')
bsinfo_fname.pack(side='top', anchor='nw')

bs_buttons = Tkinter.Frame(window_bs)
bs_buttons.pack(side='top', fill='x', expand=1)

Tkinter.Button(bs_buttons, text="Open .bit...", command=launch_open_dialog).pack(side='left')
set_fpga_model_button = Tkinter.Button(bs_buttons, text="Set FPGA model...", command=set_bitstr_fpga)
set_fpga_model_button.pack(side='left')
Tkinter.Button(bs_buttons, text="View instructions", command=bitstr_dump).pack(side='left')

# ?TODO? "Save bitstream" (with updated or removed CRC)



## Bitstream info ##

bsinfo_labelframe = Tkinter.LabelFrame(window_bs, text="File info")#, padx=5, pady=5)
bsinfo_labelframe.pack(side='top', fill='both', expand=1)

bsinfo_stringvar = Tkinter.StringVar(value="\n\n")
bsinfo = Tkinter.Label(bsinfo_labelframe, textvariable=bsinfo_stringvar, justify='left', anchor='nw')
bsinfo.pack(side='top', anchor='nw', fill='both', expand=1)



## PBS action buttons ##

pbs_buttons = Tkinter.Frame(window_pbs)
pbs_buttons.pack(side='right', fill='y')

#~ Tkinter.Button(pbs_buttons, text="Extract PBS...", command=extract_pbs).pack(side='top', anchor='e')
extract_button = Tkinter.Button(pbs_buttons, text="Extract PBS...", command=extract_pbs, state='disabled')
extract_button.pack(side='top', anchor='e')

# ?TODO? "Insert PBS..." (and fix or remove CRC?)
# ?TODO? "Set to zero" (and fix or remove CRC?)



## Bitstream coordinates ##

coords_frame = Tkinter.Frame(window_pbs)
coords_frame.pack(side='left')

box_Y0 = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)
box_Yf = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)
box_X0 = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)
box_Xf = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)
box_W0 = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)
box_Wf = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)
box_F0 = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)
box_Ff = Tkinter.Spinbox(coords_frame, width=3, justify='right', from_=0, to=999)

all_rows()  # Blank fields (blank = unlimited)
all_cols()
all_word()
all_frms()

Tkinter.Label(coords_frame, text=  "Rows ").grid(row=0, column=0, sticky='e')
Tkinter.Label(coords_frame, text=  "Cols ").grid(row=1, column=0, sticky='e')
Tkinter.Label(coords_frame, text= "Words ").grid(row=2, column=0, sticky='e')
Tkinter.Label(coords_frame, text="Frames ").grid(row=3, column=0, sticky='e')

box_Y0.grid(row=0, column=1)
box_X0.grid(row=1, column=1)
box_W0.grid(row=2, column=1)
box_F0.grid(row=3, column=1)

Tkinter.Label(coords_frame, text=" to ").grid(row=0, column=2)
Tkinter.Label(coords_frame, text=" to ").grid(row=1, column=2)
Tkinter.Label(coords_frame, text=" to ").grid(row=2, column=2)
Tkinter.Label(coords_frame, text=" to ").grid(row=3, column=2)

box_Yf.grid(row=0, column=3)
box_Xf.grid(row=1, column=3)
box_Wf.grid(row=2, column=3)
box_Ff.grid(row=3, column=3)

Tkinter.Button(coords_frame, text="All", command=all_rows, padx=5, pady=1).grid(row=0, column=4)
Tkinter.Button(coords_frame, text="All", command=all_cols, padx=5, pady=1).grid(row=1, column=4)
Tkinter.Button(coords_frame, text="All", command=all_word, padx=5, pady=1).grid(row=2, column=4)
Tkinter.Button(coords_frame, text="All", command=all_frms, padx=5, pady=1).grid(row=3, column=4)

# ?TODO? scroll -> box_*.invoke('buttonup')



## Bottom buttons ##

Tkinter.Button(window_quit, text="Close", command=window.quit).pack(side='right')

Tkinter.Button(window_quit, text="Help", command=program_help, state='disabled').pack(side='left')



## OK, let's go ##

window.mainloop()
