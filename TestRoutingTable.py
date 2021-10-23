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
    s.runTime(120);

    # for node in s.moteids:
    s.routeDMP(4);
    s.runTime(10);

if __name__ == '__main__':
    main()
