#!/usr/bin/env python
"""Where does WRF's colder/stronger northerly over the northern range come from? Zone means, ICON (met_em native levels + surface series) vs WRF runs.
Zones (box 11.30-11.85E): FORE = Bavarian foreland 47.65-47.95N, terrain <900 m; KARW = Karwendel interior 47.42-47.58N; CREST = >1800 m in 47.27-47.42N;
LEE = south-facing slope (terrain rising northward >8.5 deg, 800-2000 m, 47.25-47.40N); FLOOR = <700 m in 47.22-47.40N. Each model on the WRF grid (met_em is ICON on that grid).
Part 1: v and theta in 0-300 m AGL per zone, every available frame 13:00-15:00 (first-hour forensics). Part 2: v by height ASL over FORE and KARW, hourly 13-17.
Part 3: surface heat input FORE / Alpine interior (>1000 m, whole domain) / whole domain land, ICON series vs runs.
Usage: python northerly_origin_check.py RUN[=SEGS] ..."""
import glob, sys, numpy as np, netCDF4 as nc, warnings; warnings.filterwarnings("ignore")
D="/gpfs/data/fs72996/ewahl"; R={}
for a in sys.argv[1:] or ["X17=X17a+X17b"]:
    lab,_,segs=a.partition("="); R[lab]={f.split("d01_")[1][:16]:f for s in (segs.split("+") if segs else [lab]) for f in glob.glob(f"{D}/exp/{s}/wrf_output/*/wrfout_d01_*.nc")+glob.glob(f"{D}/exp/{s}/temp/branko/wrfout_d01_*.nc")}
def wrf_fields(f):
    d=nc.Dataset(f); ph=(np.asarray(d["PH"][0])+np.asarray(d["PHB"][0]))/9.81; z=0.5*(ph[:-1]+ph[1:]); U,V=np.asarray(d["U"][0]),np.asarray(d["V"][0]); u=0.5*(U[:,:,:-1]+U[:,:,1:]); v=0.5*(V[:,:-1]+V[:,1:])
    ca,sa=np.asarray(d["COSALPHA"][0]),np.asarray(d["SINALPHA"][0]); ve=v*ca+u*sa; th=np.asarray(d["T"][0])+300; sfc={k:np.asarray(d[k][0]) for k in ("HFX","LH","T2","SWDOWN")}; d.close(); return z,ve,th,sfc
def icon_fields(f):
    d=nc.Dataset(f); z=np.asarray(d["GHT"][0]); p=np.asarray(d["PRES"][0]); T=np.asarray(d["TT"][0]); U,V=np.asarray(d["UU"][0]),np.asarray(d["VV"][0]); u=0.5*(U[:,:,:-1]+U[:,:,1:]); v=0.5*(V[:,:-1]+V[:,1:])
    if "COSALPHA" in d.variables: ca,sa=np.asarray(d["COSALPHA"][0]),np.asarray(d["SINALPHA"][0]); v=v*ca+u*sa
    d.close(); th=T*(1e5/p)**0.2854; o=np.argsort(z[:,0,0]); return z[o][1:],v[o][1:],th[o][1:],None
g=nc.Dataset(next(iter(R[list(R)[0]].values()))); la,lo,hg,lm=[np.asarray(g[k][0]) for k in ("XLAT","XLONG","HGT","LANDMASK")]; dx=float(g.DX); g.close()
lonb=(lo>11.30)&(lo<11.85); dhdy=np.gradient(hg,dx,axis=0)
Z={"FORE":lonb&(la>47.65)&(la<47.95)&(hg<900),"KARW":lonb&(la>47.42)&(la<47.58),"CREST":lonb&(la>47.27)&(la<47.42)&(hg>1800),"LEE":lonb&(la>47.25)&(la<47.40)&(dhdy>np.tan(np.radians(8.5)))&(hg>800)&(hg<2000),"FLOOR":lonb&(la>47.22)&(la<47.40)&(hg<700)}
print("zones, cells / mean height:", {k:(int(m.sum()),int(hg[m].mean())) for k,m in Z.items()})
def lay(z,x,m,a,b,agl=True):
    zz=z[:,m]-(hg[m][None] if agl else 0); xx=x[:,m]; w=(zz>=a)&(zz<b); return float(np.nansum(np.where(w,xx,0))/max(w.sum(),1))
def icon_at(t): 
    f=f"{D}/WPS/metgrid_output_1712nat/met_em.d01.2025-07-17_{t[:2]}:00:00.nc"; return icon_fields(f) if t.endswith(":00") and glob.glob(f) else None
print("\n=== Part 1: 0-300 m AGL zone means, v [m/s] (negative = northerly) / theta [K]; ICON hourly, WRF every frame")
print(f"{'UT':6s}{'model':6s}"+"".join(f"{k:>16s}" for k in Z))
for t in ("13:00","13:30","14:00","14:30","15:00"):
    items=[("ICON",icon_at(t))]+[(k,wrf_fields(R[k][f"2025-07-17_{t}"])) for k in R if f"2025-07-17_{t}" in R[k]]
    for name,fl in items:
        if fl is None: continue
        z,v,th,_=fl; print(f"{t:6s}{name:6s}"+"".join(f"{lay(z,v,m,0,300):+7.1f}/{lay(z,th,m,0,300):7.1f} " for m in Z.values()))
print("\n=== Part 2: v [m/s] by height ASL over FORE and KARW, hourly")
B=((600,1000),(1000,1500),(1500,2000),(2000,2500),(2500,3500))
print(f"{'UT':4s}{'model':6s}| FORE "+" ".join(f"{a}-{b}" for a,b in B)+" | KARW (above ground only) same bands")
cache={}
for h in (13,14,15,16,17):
    t=f"{h}:00"; items=[("ICON",icon_at(t))]+[(k,wrf_fields(R[k][f"2025-07-17_{t}"])) for k in R if f"2025-07-17_{t}" in R[k]]
    for name,fl in items:
        z,v,th,sfc=fl; cache[(h,name)]=sfc
        print(f"{h:02d}  {name:6s}| "+" ".join(f"{lay(z,v,Z['FORE'],a,b,False):+9.1f}" for a,b in B)+" | "+" ".join(f"{lay(z,v,Z['KARW'],a,b,False):+9.1f}" for a,b in B))
print("\n=== Part 3: surface heat input [W/m2] and T2 [C]: FORE | Alpine interior (land >1000 m, whole domain) | all land; ICON series vs runs (13 UT WRF frame is pre-physics, skipped)")
S=nc.Dataset(f"{D}/ICON/surface_series/icon_surface_2025040100_2025071800.nc"); st=np.asarray(S["time"]); land=lm>0.5
ZZ={"FORE":Z["FORE"]&land,"ALPS>1000":land&(hg>1000),"LAND":land}
print(f"{'UT':4s}{'model':6s}"+"".join(f"| {k:>10s}: H   LE   Bo   T2 " for k in ZZ))
for h in (14,15,16,17):
    it=int(np.argmin(np.abs(st-(107+h/24.)))); rows=[("ICON",dict(HFX=np.asarray(S["SHFLX"][it]),LH=np.asarray(S["LHFLX"][it]),T2=np.asarray(S["T2D"][it])))]+[(k,cache[(h,k)]) for k in R if (h,k) in cache]
    for name,s in rows:
        print(f"{h:02d}  {name:6s}"+"".join(f"| {'':>10s} {s['HFX'][m].mean():4.0f} {s['LH'][m].mean():4.0f} {s['HFX'][m].mean()/max(s['LH'][m].mean(),1):4.2f} {s['T2'][m].mean()-273.15:5.1f} " for m in ZZ.values()))
