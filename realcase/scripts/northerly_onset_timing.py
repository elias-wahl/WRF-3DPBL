#!/usr/bin/env python
"""Onset timing of the excess low-level northerly over the northern range from high-frequency frames (X22: 5 min, 13->14 UT).
Zone means (lon 11.30-11.85E): RIM = Alpine rim 47.68-47.80N; KARW 47.42-47.58N; CREST >1800 m 47.27-47.42N; LEE = S-facing >8.5 deg 800-2000 m; FLOOR <700 m.
Per frame: v in 0-50 / 50-150 / 300-600 m AGL, w at 150 m AGL [cm/s], theta 0-300 m, q_sq 0-300 m (twice subgrid TKE, m2/s2), UST, HFX. ICON at 13 and 14 UT for reference.
Usage: python northerly_onset_timing.py RUN"""
import sys, glob, numpy as np, netCDF4 as nc, warnings; warnings.filterwarnings("ignore")
D="/gpfs/data/fs72996/ewahl"; run=sys.argv[1] if len(sys.argv)>1 else "X22"
fr=sorted(glob.glob(f"{D}/exp/{run}/wrf_output/*/wrfout_d01_*.nc")+glob.glob(f"{D}/exp/{run}/temp/branko/wrfout_d01_*.nc"))
g=nc.Dataset(fr[0]); la,lo,hg=[np.asarray(g[k][0]) for k in ("XLAT","XLONG","HGT")]; dx=float(g.DX); g.close(); dhdy=np.gradient(hg,dx,axis=0); lonb=(lo>11.30)&(lo<11.85)
Z={"RIM":lonb&(la>47.68)&(la<47.80),"KARW":lonb&(la>47.42)&(la<47.58),"CREST":lonb&(la>47.27)&(la<47.42)&(hg>1800),"LEE":lonb&(la>47.25)&(la<47.40)&(dhdy>np.tan(np.radians(8.5)))&(hg>800)&(hg<2000),"FLOOR":lonb&(la>47.22)&(la<47.40)&(hg<700)}
jj,ii=np.where(lonb&(la>47.20)&(la<47.82)); J=slice(jj.min(),jj.max()+1); I=slice(ii.min(),ii.max()+1); hgs=hg[J,I]; Zs={k:m[J,I] for k,m in Z.items()}
def lay(z,x,m,a,b):
    agl=z[:,m]-hgs[m][None]; w=(agl>=a)&(agl<b); return float((x[:,m]*w).sum()/max(w.sum(),1))
print(f"{run}: zone cells", {k:int(m.sum()) for k,m in Zs.items()})
for k in Zs:
    print(f"\n=== {k}:  UT | v 0-50 | v 50-150 | v 300-600 | w@50-300 cm/s | theta 0-300 | q_sq 0-300 | UST | HFX")
    for f in fr:
        d=nc.Dataset(f); t=f.split("d01_")[1][11:16]; ph=(np.asarray(d["PH"][0,:,J,I])+np.asarray(d["PHB"][0,:,J,I]))/9.81; z=0.5*(ph[:-1]+ph[1:])
        U=np.asarray(d["U"][0,:,J,slice(I.start,I.stop+1)]); V=np.asarray(d["V"][0,:,slice(J.start,J.stop+1),I]); u=0.5*(U[:,:,:-1]+U[:,:,1:]); v=0.5*(V[:,:-1]+V[:,1:]); ca,sa=np.asarray(d["COSALPHA"][0,J,I]),np.asarray(d["SINALPHA"][0,J,I]); ve=v*ca+u*sa
        W=np.asarray(d["W"][0,:,J,I]); w=0.5*(W[:-1]+W[1:]); th=np.asarray(d["T"][0,:,J,I])+300; q=np.asarray(d["Q_SQ"][0,:,J,I]) if "Q_SQ" in d.variables else th*0; m=Zs[k]
        print(f"{t} | {lay(z,ve,m,0,50):+5.1f} | {lay(z,ve,m,50,150):+5.1f} | {lay(z,ve,m,300,600):+5.1f} | {lay(z,w,m,50,300)*100:+6.1f} | {lay(z,th,m,0,300):7.2f} | {lay(z,q,m,0,300):5.2f} | {np.asarray(d['UST'][0,J,I])[m].mean():4.2f} | {np.asarray(d['HFX'][0,J,I])[m].mean():4.0f}"); d.close()
