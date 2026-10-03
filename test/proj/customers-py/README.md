# customers-py

Sample project: a customer database stored in one JSON file (`customers.json`).

    python3 -m customerdb list
    python3 -m customerdb add "Alan Turing" alan@example.com --city Manchester
    python3 -m customerdb update 4 --city Wilmslow
    python3 -m customerdb find ada
    python3 -m customerdb report
    python3 -m customerdb delete 4
    python3 -m unittest -v          # tests
