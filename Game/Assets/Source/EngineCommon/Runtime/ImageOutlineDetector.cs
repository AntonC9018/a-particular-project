using System.Collections.Generic;
using UnityEngine;

namespace EngineCommon
{
    public class Converter
    {
        public readonly struct Image
        {
            public readonly Color[] pixels;
            public readonly int width;
            public readonly int height;

            public Image(Color[] pixels, int width, int height)
            {
                this.pixels = pixels;
                this.width = width;
                this.height = height;
                Debug.Assert(pixels.Length == width * height);
            }

            public float GetAlphaAt(int x, int y)
            {
                if (x < 0 || x > width) return 0f;
                if (y < 0 || y > height) return 0f;
                return pixels[x + y * width].a;
            }

            public Vector2 GetPosition(int i)
            {
                int row = i / width;
                int col = i - row; 
                return new Vector2(col, row);
            }
        }

        // For now, assume 1 mesh per image
        public List<Vector2> GetVertices(Image image, float threshold)
        {
            // TODO: binary search? until we find the first edge that neighbors a transparent pixel
            
            int indexOpaque = 0;

            for (; indexOpaque < image.pixels.Length; indexOpaque++)
            {
                // Since we come from top, it means the top, left, top-left and top-right
                // are guaranteed to be transparent, which means this is the first opaque pixel in the image.
                if (image.pixels[indexOpaque].a > threshold)
                {
                    break;
                }
            }

            // If the entire image is transparent, return nothing
            if (indexOpaque == image.pixels.Length)
            {
                return new List<Vector2>();
            }

            // Now, we get an initial direction.
            // We need to find a neighboring pixel that is next to 
            int directionX;
            int directionY;

            while (true) 
            {
                int index = indexOpaque + 1;
                if (index == image.pixels.Length)
                {
                    return new List<Vector2> { image.GetPosition(index) };
                }
                if (image.pixels[index].a > threshold)
                {
                    directionX = 1;
                    directionY = 0;
                    break;
                }

                directionY = 1;
                index = indexOpaque + image.width;
                for (int i = -1; i <= 1; i++)
                {
                    index = indexOpaque + image.width + i;
                    if (index >= image.pixels.Length) break;
                    if (image.pixels[index].a > threshold)
                    {
                        directionX = i;
                        break;
                    }                        
                }
                break;
            }
            return null;
        }
    }
}