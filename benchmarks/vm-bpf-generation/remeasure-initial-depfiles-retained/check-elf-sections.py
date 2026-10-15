import re, subprocess, tempfile
from pathlib import Path

a=Path('/home/gregor/obi-bench/task3/remeasure-20261014/branch/pkg/internal/ebpf/generictracer/bpf_x86_bpfel.o')
b=Path('/home/gregor/obi-bench/task3/remeasure-20261014/main/pkg/internal/ebpf/generictracer/bpf_x86_bpfel.o')
def names(p):
    lines=subprocess.check_output(['llvm-readelf','-SW',str(p)],text=True).splitlines()
    return [m.group(1) for line in lines if (m:=re.match(r'\s*\[\s*\d+\]\s+(\S+)\s+',line)) and m.group(1)]
na,nb=names(a),names(b)
print(f'section_count={len(na)} section_names_equal={na==nb}')
diff=[]
with tempfile.TemporaryDirectory() as d:
    for i,section in enumerate(na):
        if section in ("NULL", ".bss"): continue
        left=Path(d)/f'a-{i}'; right=Path(d)/f'b-{i}'
        for obj,out in ((a,left),(b,right)):
            subprocess.run(['llvm-objcopy','--dump-section',f'{section}={out}',str(obj)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        if left.read_bytes()!=right.read_bytes(): diff.append(section)
print('different_sections='+','.join(diff))
