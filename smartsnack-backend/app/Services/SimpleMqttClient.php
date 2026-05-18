<?php

namespace App\Services;

use RuntimeException;

class SimpleMqttClient
{
    /** @var resource|null */
    private $socket = null;
    private string $host;
    private int $port;
    private ?string $username;
    private ?string $password;
    private string $clientId;

    public function __construct(
        string $host,
        int $port,
        string $clientId,
        ?string $username = null,
        ?string $password = null
    ) {
        $this->host = $host;
        $this->port = $port;
        $this->clientId = $clientId;
        $this->username = $username;
        $this->password = $password;
    }

    public function connect(int $timeoutSeconds = 10): void
    {
        $errno = 0;
        $errstr = '';
        $socket = @stream_socket_client(
            "tcp://{$this->host}:{$this->port}",
            $errno,
            $errstr,
            $timeoutSeconds,
            STREAM_CLIENT_CONNECT
        );

        if ($socket === false) {
            throw new RuntimeException("Broker MQTT tidak tersedia: {$errstr} ({$errno})");
        }

        stream_set_timeout($socket, $timeoutSeconds);
        $this->socket = $socket;

        $flags = 0x02; // clean session
        $payload = $this->packString($this->clientId);
        if ($this->username !== null && $this->username !== '') {
            $flags |= 0x80;
            if ($this->password !== null && $this->password !== '') {
                $flags |= 0x40;
            }
        }

        if (($flags & 0x80) !== 0) {
            $payload .= $this->packString($this->username ?? '');
        }
        if (($flags & 0x40) !== 0) {
            $payload .= $this->packString($this->password ?? '');
        }

        $variableHeader = $this->packString('MQTT') . chr(0x04) . chr($flags) . pack('n', 60);
        $packet = chr(0x10) . $this->encodeRemainingLength(strlen($variableHeader . $payload)) . $variableHeader . $payload;
        $this->write($packet);

        [$type, $data] = $this->readPacket();
        if ($type !== 2 || strlen($data) < 2 || ord($data[1]) !== 0) {
            throw new RuntimeException('Gagal CONNECT ke broker MQTT.');
        }
    }

    public function subscribe(string $topic, int $qos = 0): void
    {
        $packetId = random_int(1, 65535);
        $payload = $this->packString($topic) . chr($qos);
        $variableHeader = pack('n', $packetId);
        $packet = chr(0x82) . $this->encodeRemainingLength(strlen($variableHeader . $payload)) . $variableHeader . $payload;
        $this->write($packet);

        [$type, $data] = $this->readPacket();
        if ($type !== 9) {
            throw new RuntimeException('Gagal SUBSCRIBE ke topic MQTT.');
        }
    }

    public function publish(string $topic, string $payload): void
    {
        $data = $this->packString($topic) . $payload;
        $packet = chr(0x30) . $this->encodeRemainingLength(strlen($data)) . $data;
        $this->write($packet);
    }

    public function waitForPayload(string $topic, int $timeoutSeconds, callable $matcher): ?array
    {
        $deadline = microtime(true) + $timeoutSeconds;
        while (microtime(true) < $deadline) {
            $remaining = (int) ceil($deadline - microtime(true));
            if ($remaining <= 0) {
                break;
            }
            if (is_resource($this->socket)) {
                stream_set_timeout($this->socket, $remaining);
            }
            try {
                [$type, $data, $flags] = $this->readPacketWithFlags();
            } catch (RuntimeException $e) {
                // Saat timeout read socket, lanjut tunggu hingga deadline.
                if (str_contains($e->getMessage(), 'Tidak menerima data dari broker MQTT')) {
                    continue;
                }
                throw $e;
            }
            if ($type === 3) {
                $parsed = $this->parsePublish($data, $flags);
                if ($parsed['topic'] !== $topic) {
                    continue;
                }
                $decoded = json_decode($parsed['payload'], true);
                if (!is_array($decoded)) {
                    continue;
                }
                if ($matcher($decoded) === true) {
                    return $decoded;
                }
            }
        }
        return null;
    }

    public function disconnect(): void
    {
        if (is_resource($this->socket)) {
            @fwrite($this->socket, chr(0xE0) . chr(0x00));
            @fclose($this->socket);
        }
        $this->socket = null;
    }

    public function __destruct()
    {
        $this->disconnect();
    }

    private function write(string $data): void
    {
        if (!is_resource($this->socket)) {
            throw new RuntimeException('Socket MQTT belum terkoneksi.');
        }

        $written = @fwrite($this->socket, $data);
        if ($written === false) {
            throw new RuntimeException('Gagal mengirim data ke broker MQTT.');
        }
    }

    private function readPacket(): array
    {
        [$type, $data] = $this->readPacketInternal(false);
        return [$type, $data];
    }

    private function readPacketWithFlags(): array
    {
        return $this->readPacketInternal(true);
    }

    private function readPacketInternal(bool $withFlags): array
    {
        if (!is_resource($this->socket)) {
            throw new RuntimeException('Socket MQTT belum terkoneksi.');
        }

        $header = @fread($this->socket, 1);
        if ($header === '' || $header === false) {
            throw new RuntimeException('Tidak menerima data dari broker MQTT.');
        }

        $byte1 = ord($header);
        $type = $byte1 >> 4;
        $flags = $byte1 & 0x0F;
        $remainingLength = $this->decodeRemainingLength();
        $payload = '';
        while (strlen($payload) < $remainingLength) {
            $chunk = @fread($this->socket, $remainingLength - strlen($payload));
            if ($chunk === false || $chunk === '') {
                throw new RuntimeException('Payload MQTT terputus saat dibaca.');
            }
            $payload .= $chunk;
        }

        if ($withFlags) {
            return [$type, $payload, $flags];
        }

        return [$type, $payload];
    }

    private function parsePublish(string $packet, int $flags): array
    {
        $topicLength = unpack('n', substr($packet, 0, 2))[1];
        $topic = substr($packet, 2, $topicLength);
        $offset = 2 + $topicLength;
        $qos = ($flags >> 1) & 0x03;
        if ($qos > 0) {
            $offset += 2;
        }
        $payload = substr($packet, $offset);

        return [
            'topic' => $topic,
            'payload' => $payload,
        ];
    }

    private function packString(string $value): string
    {
        return pack('n', strlen($value)) . $value;
    }

    private function encodeRemainingLength(int $length): string
    {
        $encoded = '';
        do {
            $byte = $length % 128;
            $length = intdiv($length, 128);
            if ($length > 0) {
                $byte |= 128;
            }
            $encoded .= chr($byte);
        } while ($length > 0);

        return $encoded;
    }

    private function decodeRemainingLength(): int
    {
        if (!is_resource($this->socket)) {
            throw new RuntimeException('Socket MQTT belum terkoneksi.');
        }

        $multiplier = 1;
        $value = 0;
        do {
            $encodedByteRaw = @fread($this->socket, 1);
            if ($encodedByteRaw === '' || $encodedByteRaw === false) {
                throw new RuntimeException('Gagal membaca remaining length MQTT.');
            }
            $encodedByte = ord($encodedByteRaw);
            $value += ($encodedByte & 127) * $multiplier;
            $multiplier *= 128;
        } while (($encodedByte & 128) !== 0);

        return $value;
    }
}
