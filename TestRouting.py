from TestSim import TestSim

def main():
    s = TestSim();
    s.runTime(10);
    # s.loadTopo("long_ring.topo");
    # s.loadTopo("long_line.topo");
    # s.loadTopo("example.topo");
    s.loadTopo("project1.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.ROUTING_CHANNEL);
    # s.addChannel(s.FLOODING_CHANNEL);
    s.addChannel(s.NEIGHBOR_CHANNEL);

    # wait for neighbor discovery to stabilize
    s.runTime(60);

    s.ping(8, 2, "Hello, World");
    s.runTime(10);

    # check that every node can ping every other node
    # for src in range(1, s.numMote+1):
    #     for dest in range(1, s.numMote+1):
    #         if src != dest:
    #             print ""
    #             s.ping(src, dest, "Hello, World");
    #             s.runTime(10);

    s.moteOff(3);

    s.runTime(60);

    s.ping(8, 2, "Hello, World");
    s.runTime(10);

if __name__ == '__main__':
    main()
