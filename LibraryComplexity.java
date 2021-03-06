/**
 * Taken from PicardTools 
 */
import java.text.NumberFormat;
import java.text.ParseException;
import java.util.Locale;
import java.io.FileReader;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.File;
class LibraryComplexity {
  public static void main(String[] args) {
    if (args.length != 2 && args.length != 3 && args.length != 1) {
      System.out.println("Usage: java LibraryComplexity <directory> <output file>");
      System.out.println("     : java LibraryComplexity <unique> <pcr> <opt>");
      System.exit(0);
    }
    NumberFormat nf = NumberFormat.getInstance(Locale.US);

    BufferedReader reader = null;
    long readPairs = 0;
    long uniqueReadPairs = 0;
    long opticalDups = 0;
    long totalReadPairs = 0;
    if (args.length == 2 || args.length==1) {
      try {
        File f = new File(args[0] + "/opt_dups.txt");
        if (f.exists()) {
          reader = new BufferedReader(new FileReader(f));
          while (reader.readLine() != null) opticalDups++;
          reader.close();
        }
        
        f = new File(args[0] + "/merged_nodups.txt");
        if (f.exists()) {
          reader = new BufferedReader(new FileReader(f));
          while (reader.readLine() != null) uniqueReadPairs++;
          reader.close();				
        }
        f = new File(args[0] + "/dups.txt");
        if (f.exists()) {
          reader = new BufferedReader(new FileReader(args[0] + "/dups.txt"));
          while (reader.readLine() != null) readPairs++;
          reader.close();				
          readPairs += uniqueReadPairs; 
        }
        String fname = "inter.txt";
        if (args.length == 2) fname = args[1];
        f = new File(args[0] + "/" + fname);
        if (f.exists()) {
          reader = new BufferedReader(new FileReader(args[0] + "/" + fname));
          String line = reader.readLine();
          boolean done = false;
          while (line != null && !done) {
            if (line.contains("Sequenced Read")) {
              String[] parts = line.split(":");
              try {
                totalReadPairs = nf.parse(parts[1].trim()).longValue();
              }
              catch (ParseException e) {
                totalReadPairs = 0;
              }
              done = true;
            }
            line = reader.readLine(); 
          }
          reader.close();
        }
      } catch (IOException error) {
        System.err.println("Problem counting lines in merged_nodups and dups");
        System.exit(1);
      }
    }
    else {
      try {
        uniqueReadPairs = Integer.valueOf(args[0]);
        readPairs = Integer.valueOf(args[1]);
        opticalDups = Integer.valueOf(args[2]);
      }
      catch (NumberFormatException error) {
        System.err.println("When called with three arguments, must be integers");
        System.exit(1);
      }
      readPairs += uniqueReadPairs;
    }
    long result;
    try {
      result = estimateLibrarySize(readPairs, uniqueReadPairs);
    }
    catch (NullPointerException e) {
      System.err.println("Library complexity undefined when total = " + readPairs + " and unique = " + uniqueReadPairs);
      return;
    }
    NumberFormat decimalFormat = NumberFormat.getPercentInstance();
    decimalFormat.setMinimumFractionDigits(2);
    decimalFormat.setMaximumFractionDigits(2);

    long result2 = readPairs*readPairs/(2*(readPairs-uniqueReadPairs));
    
    System.out.print("Unique Reads: " + NumberFormat.getInstance().format(uniqueReadPairs) + " ");
    if (totalReadPairs > 0) {
      System.out.println("(" + decimalFormat.format(uniqueReadPairs/(double)totalReadPairs) + ")");
    }
    else {
      System.out.println();
    }

    System.out.print("PCR Duplicates: " + nf.format(readPairs - uniqueReadPairs) + " ");
    if (totalReadPairs > 0) {
      System.out.println("(" + decimalFormat.format((readPairs - uniqueReadPairs)/(double)totalReadPairs) + ")");
    }
    else {
      System.out.println();
    }
    System.out.print("Optical Duplicates: " + nf.format(opticalDups) + " ");
    if (totalReadPairs > 0) {
      System.out.println("(" + decimalFormat.format(opticalDups/(double)totalReadPairs) + ")");
    }
    else {
      System.out.println();
    }

    System.out.println("Library Complexity Estimate: " + nf.format(result));
    //    System.out.println("Library complexity (old): " + nf.format(result2));
		
  }

  /**
   * Estimates the size of a library based on the number of paired end molecules 
   * observed and the number of unique pairs observed.
   * <br>
   * Based on the Lander-Waterman equation that states:<br>
   *     C/X = 1 - exp( -N/X )<br>
   * where<br>
   *     X = number of distinct molecules in library<br>
   *     N = number of read pairs<br>
   *     C = number of distinct fragments observed in read pairs<br>
   */
  public static Long estimateLibrarySize(final long readPairs, 
                                         final long uniqueReadPairs) {
    final long readPairDuplicates = readPairs - uniqueReadPairs;
    
    if (readPairs > 0 && readPairDuplicates > 0) {
	    long n = readPairs;
	    long c = uniqueReadPairs;
	    
	    double m = 1.0, M = 100.0;
	    
	    if (c >= n || f(m*c, c, n) < 0) {
        throw new IllegalStateException("Invalid values for pairs and unique pairs: " + n + ", " + c);
	    }
      
	    while( f(M*c, c, n) >= 0 ) {
        m = M;
        M *= 10.0;
	    }
      
	    double r = (m+M)/2.0;
	    double u = f( r * c, c, n );
	    int i = 0;
      
	    while (u != 0 && i < 1000) {
        if (u > 0) m = r;
        else M = r;
        r = (m+M)/2.0;
        u = f( r * c, c, n );
        i++;
	    }
	    if (i == 1000) {
        System.err.println("Iterated 1000 times, returning estimate");
	    }
	    
	    return (long) (c * (m+M)/2.0);
    }
    else {
	    return null;
    }
  }
  
  /** Method that is used in the computation of estimated library size. */
  private static double f(double x, double c, double n) {
    return c/x - 1 + Math.exp(-n/x);
  }
}    
