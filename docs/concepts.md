# Important information

## To enable MIG

Verify that MIG is enabled
```bash
nvidia-smi --query-gpu=mig.mode.current,mig.mode.pending --format=csv
```

Enable:

```bash
sudo nvidia-smi -i <GPU> -mig 1
```


Verify MIG:

```bash
nvidia-smi -i <GPU> --query-gpu=mig.mode.current --format=csv
```

See available configurations:

```bash
sudo nvidia-smi mig -i <GPU> -lgip
```

Assign GPU instances:

```bash
sudo nvidia-smi mig -i <GPU> -cgi 19,19,19,19,19,19,19
```

Assign compute instances:

```bash
sudo nvidia-smi mig -i <GPU> -cci
```

Profit.
