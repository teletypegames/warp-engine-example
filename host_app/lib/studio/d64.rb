module Studio
  # A 1541 disk image (D64, 35 tracks) with PRG and SEQ files, the way VICE's
  # c1541 writes them: names in PETSCII upper case, a BAM on 18/0, the
  # directory from 18/1, the files from track 1 upwards.
  class D64
    SECTOR = 256
    DIR_TRACK = 18
    TYPES = { prg: 0x82, seq: 0x81 }.freeze

    def self.sectors_on(track)
      return 21 if track <= 17
      return 19 if track <= 24
      return 18 if track <= 30

      17
    end

    def initialize(name, id = "01")
      @name = name
      @id = id
      @data = "\0".b * (1..35).sum { |track| self.class.sectors_on(track) } * SECTOR
      @used = Hash.new { |hash, track| hash[track] = [] }
      @entries = []
      mark(DIR_TRACK, 0)
      mark(DIR_TRACK, 1)
    end

    def add(name, bytes, type: :prg)
      chunks = bytes.b.scan(/.{1,254}/m)
      chunks = [ "".b ] if chunks.empty?
      blocks = chunks.map { allocate }
      chunks.each_with_index do |chunk, index|
        following = blocks[index + 1]
        link = following ? following.pack("CC") : [ 0, chunk.bytesize + 1 ].pack("CC")
        write(*blocks[index], link + chunk)
      end
      @entries << { name: name, type: type, start: blocks.first, size: blocks.size }
      self
    end

    def to_s
      write_directory
      write_bam
      @data
    end

    private

    def offset(track, sector) = ((1...track).sum { |t| self.class.sectors_on(t) } + sector) * SECTOR

    def write(track, sector, bytes)
      @data[offset(track, sector), bytes.bytesize] = bytes
    end

    def mark(track, sector) = @used[track] << sector

    def allocate
      (1..35).each do |track|
        next if track == DIR_TRACK

        free = (0...self.class.sectors_on(track)).find { |sector| !@used[track].include?(sector) }
        next unless free

        mark(track, free)
        return [ track, free ]
      end
      raise ArgumentError, "the disk is full"
    end

    def petscii(text, length)
      text.upcase.b.ljust(length, "\xA0".b)[0, length]
    end

    def write_directory
      raise ArgumentError, "at most 8 files on this disk" if @entries.size > 8

      sector = [ 0, 0xFF ].pack("CC").b
      @entries.each_with_index do |entry, index|
        sector << [ 0, 0 ].pack("CC") if index.positive?
        sector << [ TYPES.fetch(entry[:type]), *entry[:start] ].pack("CCC")
        sector << petscii(entry[:name], 16) << ("\0".b * 9) << [ entry[:size] ].pack("v")
      end
      write(DIR_TRACK, 1, sector.ljust(SECTOR, "\0".b))
    end

    def write_bam
      bam = [ DIR_TRACK, 1, 0x41, 0 ].pack("CCCC").b
      (1..35).each do |track|
        count = self.class.sectors_on(track)
        bits = (0...count).reject { |sector| @used[track].include?(sector) }.sum { |sector| 1 << sector }
        bam << [ (0...count).count { |sector| !@used[track].include?(sector) }, bits & 0xFF, (bits >> 8) & 0xFF, (bits >> 16) & 0xFF ].pack("C*")
      end
      bam << petscii(@name, 16) << "\xA0\xA0".b << petscii(@id, 2) << "\xA0".b << "2A".b << "\xA0\xA0\xA0\xA0".b
      write(DIR_TRACK, 0, bam.ljust(SECTOR, "\0".b))
    end
  end
end
