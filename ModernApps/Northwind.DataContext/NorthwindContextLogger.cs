using static System.Environment;

namespace Northwind.EntityModels;

/// <summary>
/// Invoke object with static method for logging 
/// <br/>
/// Defined within Northwind.EntityModels as the rest of related models.
/// </summary>
public class NorthwindContextLogger
{
    /// <summary>
    /// Append the passed <paramref name="message"/> string into a txt date stamp file 
    /// </summary>
    /// <param name="message">The information worthy of saving within a txt log file</param>
    public static void WriteLine(string message)
    {
        string folder = Path.Combine(GetFolderPath(SpecialFolder.DesktopDirectory), "book_logs");
        if (!Directory.Exists(folder)) Directory.CreateDirectory(folder);
        string dateStamp = DateTime.Now.ToString("yyyyMMdd");
        string path = Path.Combine(folder, $"northwindlog_{dateStamp}.txt");
        StreamWriter textFile = File.AppendText(path);
        textFile.WriteLine($"[{DateTime.Now.ToString("yyyyMMdd_HHmmss")}] - {message}");
        textFile.Close();
    }
}
