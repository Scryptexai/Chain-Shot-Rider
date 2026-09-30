using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace ChainRider.EditorTools
{
    /// <summary>
    /// Minimal JSON reader used by ConfigImporter.
    ///
    /// Why not JsonUtility: JsonUtility requires a [Serializable] mirror class for
    /// every node, which means every rename in arena_config.json silently
    /// deserializes to a default value instead of failing. A generic tree plus
    /// explicit, named lookups lets the importer report a missing key loudly.
    ///
    /// Produces: Dictionary&lt;string, object&gt;, List&lt;object&gt;, string, double, bool, null.
    /// Editor-only, so allocation is irrelevant here.
    /// </summary>
    public static class MiniJson
    {
        public static object Parse(string json)
        {
            int i = 0;
            object value = ParseValue(json, ref i);
            SkipWhitespace(json, ref i);
            if (i < json.Length) throw new FormatException($"Trailing characters at index {i}");
            return value;
        }

        private static object ParseValue(string s, ref int i)
        {
            SkipWhitespace(s, ref i);
            if (i >= s.Length) throw new FormatException("Unexpected end of JSON");

            char c = s[i];
            switch (c)
            {
                case '{': return ParseObject(s, ref i);
                case '[': return ParseArray(s, ref i);
                case '"': return ParseString(s, ref i);
                case 't': Expect(s, ref i, "true"); return true;
                case 'f': Expect(s, ref i, "false"); return false;
                case 'n': Expect(s, ref i, "null"); return null;
                default: return ParseNumber(s, ref i);
            }
        }

        private static Dictionary<string, object> ParseObject(string s, ref int i)
        {
            var dict = new Dictionary<string, object>();
            i++;                                   // '{'
            SkipWhitespace(s, ref i);
            if (i < s.Length && s[i] == '}') { i++; return dict; }

            while (true)
            {
                SkipWhitespace(s, ref i);
                string key = ParseString(s, ref i);
                SkipWhitespace(s, ref i);
                if (s[i] != ':') throw new FormatException($"Expected ':' at index {i}");
                i++;
                dict[key] = ParseValue(s, ref i);
                SkipWhitespace(s, ref i);
                if (i >= s.Length) throw new FormatException("Unterminated object");
                if (s[i] == ',') { i++; continue; }
                if (s[i] == '}') { i++; return dict; }
                throw new FormatException($"Expected ',' or '}}' at index {i}");
            }
        }

        private static List<object> ParseArray(string s, ref int i)
        {
            var list = new List<object>();
            i++;                                   // '['
            SkipWhitespace(s, ref i);
            if (i < s.Length && s[i] == ']') { i++; return list; }

            while (true)
            {
                list.Add(ParseValue(s, ref i));
                SkipWhitespace(s, ref i);
                if (i >= s.Length) throw new FormatException("Unterminated array");
                if (s[i] == ',') { i++; continue; }
                if (s[i] == ']') { i++; return list; }
                throw new FormatException($"Expected ',' or ']' at index {i}");
            }
        }

        private static string ParseString(string s, ref int i)
        {
            if (s[i] != '"') throw new FormatException($"Expected string at index {i}");
            i++;
            var sb = new StringBuilder();
            while (true)
            {
                if (i >= s.Length) throw new FormatException("Unterminated string");
                char c = s[i++];
                if (c == '"') return sb.ToString();
                if (c != '\\') { sb.Append(c); continue; }

                char esc = s[i++];
                switch (esc)
                {
                    case '"': sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case '/': sb.Append('/'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'n': sb.Append('\n'); break;
                    case 'r': sb.Append('\r'); break;
                    case 't': sb.Append('\t'); break;
                    case 'u':
                        sb.Append((char)Convert.ToInt32(s.Substring(i, 4), 16));
                        i += 4;
                        break;
                    default: throw new FormatException($"Bad escape '\\{esc}'");
                }
            }
        }

        private static double ParseNumber(string s, ref int i)
        {
            int start = i;
            while (i < s.Length && (char.IsDigit(s[i]) || s[i] == '-' || s[i] == '+' ||
                                    s[i] == '.' || s[i] == 'e' || s[i] == 'E')) i++;
            string text = s.Substring(start, i - start);
            if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out double d))
                throw new FormatException($"Bad number '{text}' at index {start}");
            return d;
        }

        private static void Expect(string s, ref int i, string literal)
        {
            if (i + literal.Length > s.Length || s.Substring(i, literal.Length) != literal)
                throw new FormatException($"Expected '{literal}' at index {i}");
            i += literal.Length;
        }

        private static void SkipWhitespace(string s, ref int i)
        {
            while (i < s.Length && char.IsWhiteSpace(s[i])) i++;
        }
    }

    /// <summary>
    /// Typed, loud accessors over the parsed tree. Every miss throws with the full
    /// path, so a renamed config key fails the import instead of quietly producing
    /// a zero that would later look like a balance bug.
    /// </summary>
    public sealed class JsonNode
    {
        private readonly object _value;
        private readonly string _path;

        public JsonNode(object value, string path = "$")
        {
            _value = value;
            _path = path;
        }

        public bool Exists => _value != null;

        public JsonNode this[string key]
        {
            get
            {
                if (_value is not Dictionary<string, object> dict)
                    throw new FormatException($"{_path} is not an object");
                if (!dict.TryGetValue(key, out object child))
                    throw new FormatException($"Missing key: {_path}.{key}");
                return new JsonNode(child, $"{_path}.{key}");
            }
        }

        public JsonNode this[int index]
        {
            get
            {
                if (_value is not List<object> list)
                    throw new FormatException($"{_path} is not an array");
                if (index < 0 || index >= list.Count)
                    throw new FormatException($"Index {index} out of range at {_path}");
                return new JsonNode(list[index], $"{_path}[{index}]");
            }
        }

        /// <summary>Optional lookup: returns a fallback instead of throwing.</summary>
        public JsonNode Opt(string key)
        {
            if (_value is Dictionary<string, object> dict && dict.TryGetValue(key, out object child))
                return new JsonNode(child, $"{_path}.{key}");
            return new JsonNode(null, $"{_path}.{key}");
        }

        public int Count => _value is List<object> list ? list.Count : 0;

        public float AsFloat()
        {
            if (_value is double d) return (float)d;
            throw new FormatException($"{_path} is not a number");
        }

        public float AsFloat(float fallback) => _value is double d ? (float)d : fallback;

        public int AsInt()
        {
            if (_value is double d) return (int)Math.Round(d);
            throw new FormatException($"{_path} is not a number");
        }

        public int AsInt(int fallback) => _value is double d ? (int)Math.Round(d) : fallback;

        public bool AsBool(bool fallback = false) => _value is bool b ? b : fallback;

        public string AsString()
        {
            if (_value is string s) return s;
            throw new FormatException($"{_path} is not a string");
        }

        public string AsString(string fallback) => _value is string s ? s : fallback;

        public float[] AsFloatArray()
        {
            if (_value is not List<object> list) throw new FormatException($"{_path} is not an array");
            var result = new float[list.Count];
            for (int i = 0; i < list.Count; i++) result[i] = (float)(double)list[i];
            return result;
        }

        public int[] AsIntArray()
        {
            if (_value is not List<object> list) throw new FormatException($"{_path} is not an array");
            var result = new int[list.Count];
            for (int i = 0; i < list.Count; i++) result[i] = (int)Math.Round((double)list[i]);
            return result;
        }

        public string[] AsStringArray()
        {
            if (_value is not List<object> list) throw new FormatException($"{_path} is not an array");
            var result = new string[list.Count];
            for (int i = 0; i < list.Count; i++) result[i] = (string)list[i];
            return result;
        }
    }
}
