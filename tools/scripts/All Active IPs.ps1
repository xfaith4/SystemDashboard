for ($i = 1; $i -lt 255; $i++) {
    Test-Connection "192.168.50.$i" -Count 1 -ErrorAction SilentlyContinue -Verbose
}

